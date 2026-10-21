/*
 * HCFR Colorimeter for macOS
 * Copyright (C) 2026 Jorge Velázquez
 *
 * This program is free software; you can redistribute it and/or modify it under the terms of
 * the GNU General Public License version 2 as published by the Free Software Foundation.
 * It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.
 */

/*
 * hcfr-meter: helper process that drives the colorimeter/spectro with the ArgyllCMS
 * instrument drivers included in HCFR (third_party/hcfr/Tools/spectro).
 *
 * It runs apart from the app because Argyll calls exit() on fatal errors.
 * Protocol over stdin/stdout, one command per line. Replies start with '@':
 *
 *   list          -> "@PORT <n> <name>" for each port, then "@OK"
 *   open <n> [default|crt|lcd|oled|proj]
 *                 -> "@OPENED <instrument>\t<correction>\t<1 exact | 0 approximate>\t<serial>\t<1 if high res. available>" or "@ERR <msg>"
 *   read          -> spectral meters first send "@SPEC <nm short> <nm long> <n> <v1> … <vn>" (mW/m2/sr/nm), then
 *                    "@XYZ <X> <Y> <Z>" (cd/m2), "@CAL <cond hex> <msg>", "@POS wrong <msg>" or "@ERR <msg>"
 *   cal           -> "@OK", "@CAL <cond hex> <msg>" or "@ERR <msg>"
 *   settype <i>   -> selects display type/correction <i> from "types"; "@OK" or "@ERR <msg>"
 *   ident <n>     -> "@IDENT <n> <serial number>" (opens and closes the port) or "@ERR <msg>"
 *   pos           -> "@POS ok" or "@POS wrong <instruction>" (e.g. i1d3 diffuser in place)
 *   highres <0|1>   -> spectrometer resolution: 0 = standard 10 nm (default), 1 = high 3.3 nm; "@OK" or "@ERR <msg>"
 *   diffcheck <0|1> -> turns the i1d3 diffuser-position check off/on (on by default); "@OK"
 *   types         -> "@TYPE <i>\t<description>\t<disptech>\t<ccss|builtin>\trefresh=<0|1>", then "@OK"
 *   caps          -> "@CAPS tele=<0|1> ambient=<0|1> hires=<0|1> observer=<0|1> itime=<0|1>"
 *   observers     -> "@OBS <i>\t<description>" for each standard observer, then "@OK"
 *   rtype <0|1|2> -> reading type display (spot) / telephoto / ambient, as HCFR's
 *                    ArgyllMeterWrapper::connectAndStartMeter; "@RTYPE <type actually set>" or "@ERR"
 *   obs <i>       -> observer for CCSS corrections / spectral meters (icxObserverType); "@OK" or "@ERR"
 *   itime <ms> <refresh 0|1> -> minimum integration time of i1d3 / ColorMunki colorimeters
 *                    (0 = Argyll default); "@ITIME <seconds set>" or "@ERR"
 *   hires <0|1>   -> high resolution spectral mode (i1Pro, ColorMunki); "@OK"
 *   adapt <0|1>   -> HCFR's low-light averaging (off by default, as HCFR): up to 5 readings
 *                    below 10 cd/m²; "@OK"
 *   open 1000     -> simulated sensor (HCFR's "Simulated sensor"): no hardware; "stim <r> <g> <b>"
 *                    (0…1 signal of the pattern shown) sets what the next "read" returns, from a
 *                    model display (Rec.709 primaries, D65 at 120 cd/m², gamma about 2.3)
 *   quit
 *
 * Argyll diagnostic messages go to stderr.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <strings.h>
#include <math.h>

#include "copyright.h"
#include "aconfig.h"
#include "sa_config.h"
#include "numsup.h"
#include "cgats.h"
#include "xspect.h"
#include "insttypes.h"
#include "conv.h"
#include "icoms.h"
#include "inst.h"
#include "instappsup.h"
#include "disptechs.h"
#include "i1d3.h"

static icompaths *g_paths = NULL;
static inst *g_it = NULL;

/* Calibration in progress. As in Argyll's inst_handle_calibrate(), when the instrument asks
   for a set-up (e.g. i1Pro on its white tile) the next calibrate() call must pass back the
   type and condition it returned, meaning "the user did it". Passing inst_calc_none again made
   the i1Pro2 ask for the white tile forever. */
static int g_cal_pending = 0;
static inst_cal_type g_calt = inst_calt_needed;
static inst_cal_cond g_calc = inst_calc_none;


static void log_to_stderr(void *cntx, a1log *p, char *fmt, va_list args) {
	vfprintf(stderr, fmt, args);
	fflush(stderr);
}

static void reply(const char *fmt, ...) {
	va_list args;
	printf("@");
	va_start(args, fmt);
	vprintf(fmt, args);
	va_end(args);
	printf("\n");
	fflush(stdout);
}

static const char *inst_err(inst_code rv) {
	static char buf[512];
	if (g_it == NULL)
		return "no instrument";
	snprintf(buf, sizeof(buf), "%s (%s)", g_it->inst_interp_error(g_it, rv), g_it->interp_error(g_it, rv));
	for (char *c = buf; *c; c++)
		if (*c == '\n' || *c == '\r') *c = ' ';
	return buf;
}

/* User instructions for each calibration condition */
static const char *cal_message(inst_cal_cond cond, const char *id) {
	switch (cond & inst_calc_cond_mask) {
		case inst_calc_none:            return "No action needed";
		case inst_calc_man_em_dark:
		case inst_calc_man_ref_dark:    return "Cover the sensor (dark calibration position) and continue";
		case inst_calc_man_ref_white:
		case inst_calc_man_ref_whitek:  return "Place the meter in its calibration position (white reference) and continue";
		case inst_calc_man_cal_smode:   return "Place the meter in calibration position and continue";
		case inst_calc_emis_white:      return "Display a 100% white patch and continue";
		case inst_calc_emis_80pc:       return "Display an 80% white patch (to measure the refresh rate) and continue";
		case inst_calc_change_filter:   return "Change the meter filter and continue";
		case inst_calc_message:         return (id != NULL && id[0]) ? id : "Follow the meter instructions";
		default:                        return "Position the meter as the instrument requests and continue";
	}
}

static void cmd_list(void) {
	if (g_paths == NULL && (g_paths = new_icompaths(g_log)) == NULL) {
		reply("ERR Could not enumerate ports");
		return;
	}
	for (int i = 0; i < g_paths->npaths; i++)
		reply("PORT %d %s", i + 1, g_paths->paths[i]->name);
	reply("OK");
}

static int contains_nocase(const char *hay, const char *needle) {
	size_t n = strlen(needle);
	for (; *hay; hay++)
		if (strncasecmp(hay, needle, n) == 0)
			return 1;
	return 0;
}

/* Chooses the meter correction for a display type (crt, lcd, oled, proj).
   Looks first by technology/description (installed CCSS included), then falls back to
   refresh (CRT) or non-refresh (others). *exact = 0 if an approximation was used. */
static const char *choose_disptype(const char *type, int *exact) {
	static const char *kw_crt[]  = { "CRT", NULL };
	static const char *kw_lcd[]  = { "Non-Refresh", NULL };
	static const char *kw_oled[] = { "OLED", NULL };
	static const char *kw_proj[] = { "Projector", "DLP", NULL };
	const char **kw = kw_crt;
	int family = disptech_crt, refresh = 1, n = 0, pick = -1;
	inst_disptypesel *sel = NULL;

	if (strcmp(type, "lcd") == 0)       { kw = kw_lcd;  family = -1;            refresh = 0; } /* LCD: the meter's factory calibration */
	else if (strcmp(type, "oled") == 0) { kw = kw_oled; family = disptech_oled; refresh = 0; }
	else if (strcmp(type, "proj") == 0) { kw = kw_proj; family = disptech_dlp;  refresh = 0; }

	*exact = 1;
	if (g_it->get_disptypesel(g_it, &n, &sel, 0, 0) != inst_ok || n == 0) {
		*exact = 0;
		return "(meter has no display types)";
	}
	/* 1) HCFR CCSS spectral correction (Install/color) for that technology, as HCFR for Windows.
	   2) The meter's built-in correction for that technology.
	   Technology: 0x1000 CRT, 0x3xxx LCD, 0x4xxx OLED, 0x5xxx DLP/projector. */
	for (int pass = 0; pass < 2 && pick < 0; pass++) {
		int want_ccss = pass == 0;
		for (int i = 0; i < n && pick < 0; i++)
			if (((sel[i].flags & inst_dtflags_ccss) != 0) == want_ccss
			 && ((int)sel[i].dtech & 0xF000) == family)
				pick = i;
		for (int k = 0; kw[k] != NULL && pick < 0; k++)
			for (int i = 0; i < n && pick < 0; i++)
				if (((sel[i].flags & inst_dtflags_ccss) != 0) == want_ccss
				 && contains_nocase(sel[i].desc, kw[k]))
					pick = i;
	}
	if (pick < 0) {
		*exact = 0;
		for (int i = 0; i < n && pick < 0; i++)
			if ((sel[i].refr != 0) == refresh)
				pick = i;
	}
	if (pick < 0)
		pick = 0;
	if (g_it->set_disptype(g_it, pick) != inst_ok) {
		*exact = 0;
		return "(could not set display type)";
	}
	return sel[pick].desc;
}

/* Lists the corrections available on the open meter */
/* Instruction when the meter is not in display measuring position (e.g. diffuser in place) */
static const char *position_message(void) {
	if (g_it != NULL && g_it->get_itype(g_it) == instI1Disp3)
		return "Meter is in incorrect position: the ambient diffuser is covering the sensor. "
		       "Swing the diffuser away from the lens so the sensor can measure the display, then press OK.";
	return "Meter is in incorrect position. Set it to the display measurement position, then press OK.";
}

/* Spectral resolution of spectrometers that support it (i1Pro, i1Pro2, i1Pro3, ColorMunki):
   standard (10 nm, Argyll default) or high (3.3 nm), as HCFR's "HiRes" option */
static void cmd_highres(int on) {
	inst_code rv;
	if (g_it == NULL) { reply("ERR No instrument open"); return; }
	rv = g_it->get_set_opt(g_it, on ? inst_opt_highres : inst_opt_stdres);
	if (rv != inst_ok) { reply("ERR High resolution mode not available: %s", inst_err(rv)); return; }
	reply("OK");
}

/* Diffuser-position check of the i1d3 driver: off for meter models the app has not tested */
static int g_diffcheck = 1;
static int g_adapt = 0;   /* HCFR's "Adapt" (ArgyllSensor), off by default */

static void cmd_diffcheck(int on) {
	g_diffcheck = on != 0;
	if (g_it != NULL && g_it->get_itype(g_it) == instI1Disp3)
		((i1d3 *)g_it)->ignore_diffpos = !g_diffcheck;
	reply("OK");
}

/* Checks that the meter is in a configuration that can measure displays */
static void cmd_pos(void) {
	inst_mode modes = inst_mode_none;
	int ix = -1;
	if (g_it == NULL) { reply("ERR No instrument open"); return; }
	if (!g_diffcheck) { reply("POS ok"); return; }
	if (g_it->meas_config == NULL
	 || g_it->meas_config(g_it, &modes, NULL, &ix) != inst_ok
	 || IMODETST(modes, inst_mode_emis_spot))
		reply("POS ok");
	else
		reply("POS wrong %s", position_message());
}

static void cmd_types(void) {
	int n = 0;
	inst_disptypesel *sel = NULL;
	if (g_it == NULL) { reply("ERR No instrument open"); return; }
	if (g_it->get_disptypesel(g_it, &n, &sel, 0, 0) == inst_ok)
		for (int i = 0; i < n; i++)
			reply("TYPE %d\t%s\t%x\t%s\trefresh=%d", i, sel[i].desc, (unsigned)sel[i].dtech,
			      (sel[i].flags & inst_dtflags_ccss) ? "ccss" : "builtin", sel[i].refr);
	reply("OK");
}

/* ---- Sensor options of HCFR's Argyll meter page (ArgyllSensor.cpp / ArgyllMeterWrapper.cpp) ---- */

static void get_caps(inst_mode *cap, inst2_capability *cap2) {
	inst3_capability cap3 = 0;
	*cap = 0; *cap2 = 0;
	g_it->capabilities(g_it, cap, cap2, &cap3);
}

static int is_colorimeter(void) {
	inst_mode cap; inst2_capability cap2;
	get_caps(&cap, &cap2);
	return !IMODETST(cap, inst_mode_spectral);
}

static int supports_hires(void) {
	instType t = g_it->get_itype(g_it);
	return t == instI1Pro || t == instColorMunki || t == instI1Pro2 || t == instI1Pro3;
}

static int supports_itime(void) {
	instType t = g_it->get_itype(g_it);
	return (t == instI1Disp3 || t == instColorMunki) && is_colorimeter();
}

static void cmd_caps(void) {
	inst_mode cap; inst2_capability cap2;
	if (g_it == NULL) { reply("ERR No instrument open"); return; }
	get_caps(&cap, &cap2);
	reply("CAPS tele=%d ambient=%d hires=%d observer=%d itime=%d",
	      IMODETST(cap, inst_mode_emis_tele) ? 1 : 0, IMODETST(cap, inst_mode_emis_ambient) ? 1 : 0,
	      supports_hires(), ((cap2 & inst2_ccss) || !is_colorimeter()) ? 1 : 0, supports_itime());
}

static void cmd_observers(void) {
	for (int i = 0; i < icxOT_MAX; i++) {
		if (i == icxOT_none || i == icxOT_custom) continue;
		char *d = standardObserverDescription((icxObserverType)i);
		if (d != NULL && d[0]) reply("OBS %d\t%s", i, d);
	}
	reply("OK");
}

/* Reading type: 0 display (spot), 1 telephoto, 2 ambient; falls back as HCFR does */
static void cmd_rtype(int want) {
	inst_mode cap; inst2_capability cap2;
	inst_mode mode = inst_mode_none;
	inst_code rv;
	int got = want;
	if (g_it == NULL) { reply("ERR No instrument open"); return; }
	get_caps(&cap, &cap2);
	if (want == 1) {
		if (IMODETST(cap, inst_mode_emis_tele)) mode = inst_mode_emis_tele;
		else { mode = inst_mode_emis_spot; got = 0; }
	} else if (want == 2) {
		if (IMODETST(cap, inst_mode_emis_ambient)) mode = inst_mode_emis_ambient;
		else { mode = inst_mode_emis_spot; got = 0; }
	} else {
		if (IMODETST(cap, inst_mode_emis_spot)) mode = inst_mode_emis_spot;
		else { mode = inst_mode_emis_tele; got = 1; }
	}
	if ((rv = g_it->set_mode(g_it, mode)) != inst_ok) { reply("ERR Could not set the reading type: %s", inst_err(rv)); return; }
	get_caps(&cap, &cap2);
	if (IMODETST(cap, inst_mode_spectral))
		g_it->set_mode(g_it, mode | inst_mode_spectral);
	g_it->get_set_opt(g_it, inst_opt_trig_prog);
	reply("RTYPE %d", got);
}

static void cmd_obs(int ob) {
	inst_mode cap; inst2_capability cap2;
	inst_code rv;
	if (g_it == NULL) { reply("ERR No instrument open"); return; }
	get_caps(&cap, &cap2);
	if (!(cap2 & inst2_ccss) && is_colorimeter()) { reply("OK"); return; }   /* not applicable */
	if (ob < 0 || ob >= icxOT_MAX || ob == icxOT_none || ob == icxOT_custom) ob = icxOT_default;
	if ((rv = g_it->get_set_opt(g_it, inst_opt_set_ccss_obs, (icxObserverType)ob, NULL)) != inst_ok)
		reply("ERR Could not set the observer: %s", inst_err(rv));
	else
		reply("OK");
}

/* As HCFR: refresh displays use a whole number of refresh periods when the rate is known */
static void cmd_itime(int ms, int refresh) {
	double want = ms / 1000.0, i_time = want, rate = 0;
	inst_code rv;
	if (g_it == NULL) { reply("ERR No instrument open"); return; }
	if (!supports_itime()) { reply("ITIME 0"); return; }
	if (refresh) {
		double minint = want == 0.0 ? 0.4 : want;
		if (g_it->get_refr_rate(g_it, &rate) == inst_ok && rate > 0)
			i_time = ceil(minint * rate) / rate;
		else
			i_time = minint;
	}
	if ((rv = g_it->get_set_opt(g_it, inst_opt_set_min_int_time, i_time)) != inst_ok)
		reply("ERR Could not set the integration time: %s", inst_err(rv));
	else
		reply("ITIME %.4f", i_time);
}

static void cmd_hires(int on) {
	if (g_it != NULL && supports_hires())
		g_it->get_set_opt(g_it, on ? inst_opt_highres : inst_opt_stdres);
	reply("OK");
}

static const char *serial_of(inst *it) {
	char *sn = it->get_serial_no != NULL ? it->get_serial_no(it) : NULL;
	/* El driver i1d3 (i1 DisplayPro / ColorMunki / ColorChecker Display) no implementa
	   get_serial_no(), pero lee el numero de serie de su EEPROM en i1d3->serial_no. */
	if ((sn == NULL || sn[0] == '\0') && it->get_itype(it) == instI1Disp3)
		sn = ((i1d3 *)it)->serial_no;
	return sn != NULL ? sn : "";
}

/* Briefly opens port <n> to read its serial number (to tell identical meters apart) */
static void cmd_ident(int port) {
	inst *it;
	if (g_paths == NULL && (g_paths = new_icompaths(g_log)) == NULL) { reply("ERR Could not enumerate ports"); return; }
	if (port < 1 || port > g_paths->npaths) { reply("ERR Port %d does not exist", port); return; }
	if ((it = new_inst(g_paths->paths[port - 1], 0, g_log, NULL, NULL)) == NULL) { reply("ERR Unknown instrument"); return; }
	if (it->init_coms(it, baud_38400, fc_nc, 15.0) != inst_ok || it->init_inst(it) != inst_ok) {
		it->del(it);
		reply("ERR Port %d is busy or not responding", port);
		return;
	}
	reply("IDENT %d %s", port, serial_of(it));
	it->del(it);
}

static void cmd_open(int port, const char *type) {
	inst_code rv;
	inst_mode cap = 0;
	inst2_capability cap2 = 0;
	inst3_capability cap3 = 0;
	const char *dtype = "(fixed)";
	int exact = 1;

	g_cal_pending = 0;
	if (g_it != NULL) {
		g_it->del(g_it);
		g_it = NULL;
	}
	if (g_paths == NULL && (g_paths = new_icompaths(g_log)) == NULL) {
		reply("ERR Could not enumerate ports");
		return;
	}
	if (port < 1 || port > g_paths->npaths) {
		reply("ERR Port %d does not exist", port);
		return;
	}
	if ((g_it = new_inst(g_paths->paths[port - 1], 0, g_log, NULL, NULL)) == NULL) {
		reply("ERR Unknown instrument or not detected");
		return;
	}
	if ((rv = g_it->init_coms(g_it, baud_38400, fc_nc, 15.0)) != inst_ok) {
		reply("ERR Communication failed: %s", inst_err(rv));
		g_it->del(g_it); g_it = NULL;
		return;
	}
	if ((rv = g_it->init_inst(g_it)) != inst_ok) {
		reply("ERR Initialisation failed: %s", inst_err(rv));
		g_it->del(g_it); g_it = NULL;
		return;
	}
	g_it->capabilities(g_it, &cap, &cap2, &cap3);
	if (!IMODETST(cap, inst_mode_emis_spot)) {
		reply("ERR Instrument cannot measure displays (emissive mode)");
		g_it->del(g_it); g_it = NULL;
		return;
	}

	/* "default": like HCFR for Windows, open without forcing anything; the app then applies
	   the chosen Display with "settype" (ArgyllMeterWrapper::setDisplayType). */
	if ((cap2 & inst2_disptype) && strcmp(type, "default") != 0)
		dtype = choose_disptype(type, &exact);

	inst_mode mode = inst_mode_emis_spot;
	if (IMODETST(cap, inst_mode_spectral))
		mode |= inst_mode_spectral;
	if (strcmp(type, "crt") == 0 && g_it->check_mode(g_it, inst_mode_emis_refresh_ovd) == inst_ok)
		mode |= inst_mode_emis_refresh_ovd;
	if ((rv = g_it->set_mode(g_it, mode)) != inst_ok) {
		reply("ERR Could not set measurement mode: %s", inst_err(rv));
		g_it->del(g_it); g_it = NULL;
		return;
	}
	g_it->get_set_opt(g_it, inst_opt_trig_prog);

	reply("OPENED %s\t%s\t%d\t%s\t%d", inst_name(g_it->get_itype(g_it)), dtype, exact, serial_of(g_it),
	      IMODETST(cap, inst_mode_highres) ? 1 : 0);
}

/* Tries to calibrate; returns 1 if ready, 0 if it replied with @CAL/@ERR */
/* Starts (resume = 0) or continues (resume = 1) a calibration; returns 1 if ready, 0 if it
   replied with @CAL/@ERR */
static int do_calibrate(int report_ok, int resume) {
	inst_calc_id_type idtype = inst_calc_id_none;
	char id[CALIDLEN] = "";
	inst_code rv;

	if (!resume || !g_cal_pending) {
		g_calt = inst_calt_needed;
		g_calc = inst_calc_none;
	}
	rv = g_it->calibrate(g_it, &g_calt, &g_calc, &idtype, id);
	if ((rv & inst_mask) == inst_cal_setup) {
		g_cal_pending = 1;
		reply("CAL %x %s", (unsigned)g_calc, cal_message(g_calc, id));
		return 0;
	}
	g_cal_pending = 0;
	if (rv != inst_ok && (rv & inst_mask) != inst_unsupported) {
		reply("ERR Calibration failed: %s", inst_err(rv));
		return 0;
	}
	if (report_ok)
		reply("OK");
	return 1;
}

static void cmd_cal(void) {
	if (g_it == NULL) { reply("ERR No instrument open"); return; }
	do_calibrate(1, 1);
}

static void cmd_read(void) {
	ipatch val;
	inst_code rv;

	if (g_it == NULL) { reply("ERR No instrument open"); return; }

	memset(&val, 0, sizeof(val));
	rv = g_it->read_sample(g_it, "SPOT", &val, instNoClamp);
	if ((rv & inst_mask) == inst_needs_cal) {
		if (!do_calibrate(0, 0))
			return;
		rv = g_it->read_sample(g_it, "SPOT", &val, instNoClamp);
	}
	if ((rv & inst_mask) == inst_wrong_config) {
		reply("POS wrong %s", position_message());
		return;
	}
	if (rv != inst_ok) { reply("ERR Reading failed: %s", inst_err(rv)); return; }
	if (!val.XYZ_v) { reply("ERR Instrument returned no XYZ"); return; }

	/* HCFR adaptive averaging (ArgyllMeterWrapper::takeReading): more readings in low light */
	double X = val.XYZ[0], Y = val.XYZ[1], Z = val.XYZ[2];
	int extra = !g_adapt ? 0 : Y < 1.0 ? 4 : Y < 2.0 ? 3 : Y < 5.0 ? 2 : Y < 10.0 ? 1 : 0;
	int count = 1;
	xspect sp = val.sp;
	for (int i = 0; i < extra; i++) {
		if (g_it->read_sample(g_it, "SPOT", &val, instNoClamp) != inst_ok || !val.XYZ_v)
			break;
		X += val.XYZ[0]; Y += val.XYZ[1]; Z += val.XYZ[2];
		if (sp.spec_n > 0 && val.sp.spec_n == sp.spec_n)
			for (int k = 0; k < sp.spec_n; k++) sp.spec[k] += val.sp.spec[k];
		count++;
	}
	if (sp.spec_n > 0) {
		/* Spectrum (HCFR's Spectrum graph and spectral samples), averaged like XYZ */
		double norm = sp.norm > 0 ? sp.norm : 1.0;
		printf("@SPEC %.3f %.3f %d", sp.spec_wl_short, sp.spec_wl_long, sp.spec_n);
		for (int k = 0; k < sp.spec_n; k++) printf(" %.6g", sp.spec[k] / norm / count);
		printf("\n");
		fflush(stdout);
	}
	reply("XYZ %.6f %.6f %.6f", X / count, Y / count, Z / count);
}

/* ---- Simulated sensor (HCFR's CSimulatedSensor): a display model, no instrument ---- */
#define SIM_PORT 1000
static int g_sim = 0;
static double g_stim[3] = { 0, 0, 0 };

static double sim_noise(void) {
	return ((double)rand() / RAND_MAX - 0.5) * 0.004;
}

static void sim_read(void) {
	/* Rec.709 → XYZ (D65), channel gammas a little different and a small black level, as a real display */
	static const double m[3][3] = { { 0.4124, 0.3576, 0.1805 }, { 0.2126, 0.7152, 0.0722 }, { 0.0193, 0.1192, 0.9505 } };
	static const double gam[3] = { 2.32, 2.28, 2.36 }, gain[3] = { 1.02, 1.0, 0.97 };
	double lin[3], xyz[3];
	for (int c = 0; c < 3; c++) {
		double v = g_stim[c] < 0 ? 0 : g_stim[c] > 1 ? 1 : g_stim[c];
		lin[c] = gain[c] * pow(v, gam[c]) * 120.0;
	}
	for (int r = 0; r < 3; r++) {
		xyz[r] = 0.05 * (r == 1 ? 1.0 : r == 0 ? 0.95 : 1.09);
		for (int c = 0; c < 3; c++) xyz[r] += m[r][c] * lin[c];
		xyz[r] *= 1 + sim_noise();
	}
	reply("XYZ %f %f %f", xyz[0], xyz[1], xyz[2]);
}

/* Commands of the simulated sensor; returns 1 when handled */
static int sim_command(const char *cmd, const char *line) {
	if (strcmp(cmd, "read") == 0)          { sim_read(); return 1; }
	if (strcmp(cmd, "stim") == 0)          { sscanf(line, "%*s %lf %lf %lf", &g_stim[0], &g_stim[1], &g_stim[2]); reply("OK"); return 1; }
	if (strcmp(cmd, "types") == 0)         { reply("TYPE 0\tSimulated display\t0\tbuiltin\trefresh=0"); reply("OK"); return 1; }
	if (strcmp(cmd, "caps") == 0)          { reply("CAPS tele=0 ambient=0 hires=0 observer=0 itime=0"); return 1; }
	if (strcmp(cmd, "observers") == 0)     { reply("OK"); return 1; }
	if (strcmp(cmd, "itime") == 0)         { reply("ITIME 0"); return 1; }
	if (strcmp(cmd, "pos") == 0)           { reply("POS ok"); return 1; }
	if (strcmp(cmd, "cal") == 0 || strcmp(cmd, "settype") == 0 || strcmp(cmd, "rtype") == 0 || strcmp(cmd, "obs") == 0
	    || strcmp(cmd, "hires") == 0 || strcmp(cmd, "adapt") == 0 || strcmp(cmd, "diffcheck") == 0
	    || strcmp(cmd, "highres") == 0) { reply("OK"); return 1; }
	return 0;
}

int main(int argc, char *argv[]) {
	char line[256];

	set_exe_path(argv[0]);
	g_log->tag = "hcfr-meter";
	g_log->logv = log_to_stderr;
	g_log->logd = log_to_stderr;
	g_log->loge = log_to_stderr;

	reply("READY");
	while (fgets(line, sizeof(line), stdin) != NULL) {
		char cmd[32] = "", arg2[8] = "crt";
		int arg1 = 0;
		sscanf(line, "%31s %d %7s", cmd, &arg1, arg2);
		if (strcmp(cmd, "open") == 0 && arg1 == SIM_PORT) {
			if (g_it != NULL) { g_it->del(g_it); g_it = NULL; }
			g_sim = 1;
			reply("OPENED Simulated sensor\tSimulated display\t1\tSIM-0001\t0");
			continue;
		}
		if (strcmp(cmd, "open") == 0) g_sim = 0;
		if (g_sim && sim_command(cmd, line)) continue;
		if (strcmp(cmd, "caps") == 0)           { cmd_caps(); continue; }
		if (strcmp(cmd, "observers") == 0)      { cmd_observers(); continue; }
		if (strcmp(cmd, "rtype") == 0)          { cmd_rtype(arg1); continue; }
		if (strcmp(cmd, "obs") == 0)            { cmd_obs(arg1); continue; }
		if (strcmp(cmd, "itime") == 0)          { cmd_itime(arg1, atoi(arg2)); continue; }
		if (strcmp(cmd, "hires") == 0)          { cmd_hires(arg1); continue; }
		if (strcmp(cmd, "adapt") == 0)          { g_adapt = arg1 != 0; reply("OK"); continue; }
		if (strcmp(cmd, "list") == 0)      cmd_list();
		else if (strcmp(cmd, "open") == 0) cmd_open(arg1, arg2);
		else if (strcmp(cmd, "read") == 0) cmd_read();
		else if (strcmp(cmd, "cal") == 0)  cmd_cal();
		else if (strcmp(cmd, "types") == 0) cmd_types();
		else if (strcmp(cmd, "ident") == 0) cmd_ident(arg1);
		else if (strcmp(cmd, "pos") == 0)   cmd_pos();
		else if (strcmp(cmd, "diffcheck") == 0) cmd_diffcheck(arg1);
		else if (strcmp(cmd, "highres") == 0) cmd_highres(arg1);
		else if (strcmp(cmd, "settype") == 0) {
			if (g_it != NULL && g_it->set_disptype(g_it, arg1) == inst_ok) reply("OK");
			else reply("ERR Could not set correction %d", arg1);
		}
		else if (strcmp(cmd, "quit") == 0) break;
		else if (cmd[0] != '\0')           reply("ERR Unknown command: %s", cmd);
	}
	if (g_it != NULL) g_it->del(g_it);
	if (g_paths != NULL) g_paths->del(g_paths);
	return 0;
}

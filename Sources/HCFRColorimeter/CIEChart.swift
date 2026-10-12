// HCFR Colorimeter for macOS
// Copyright (C) 2026 Jorge Velázquez
// CIE diagram added in 2026: a port of HCFR's CIE chart (Tools/CIEChartImage.cpp by Georges
// Gallerand and Views/CIEChartView.cpp), Copyright (c) 2005-2011 Association Homecinema
// Francophone, GNU GPL. Same spectral tables, colors, scales and markers.
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import SwiftUI

/// HCFR's tables (Tools/CIEChartImage.cpp): spectral chromaticities every 2 nm from 520 nm,
/// left side of the "tongue" going down to violet and right side going to red, in CIE xy and
/// CIE u'v', and the black body (Planckian) locus from 2600 to 40000 K.
enum CIETables {
    static let xyLeft: [(Double, Double)] = [
        (0.093218329, 0.840634868),
        (0.078823221, 0.839593793),
        (0.064847649, 0.834844596),
        (0.050622056, 0.826919712),
        (0.036449887, 0.814976286),
        (0.023816396, 0.796175656),
        (0.014239761, 0.767706546),
        (0.008018852, 0.730183784),
        (0.004712871, 0.686564943),
        (0.003636384, 0.639843022),
        (0.004182885, 0.591944317),
        (0.005959173, 0.544243383),
        (0.009334011, 0.496734903),
        (0.014769904, 0.449089257),
        (0.022216179, 0.401746848),
        (0.031165264, 0.355795702),
        (0.041078948, 0.312238568),
        (0.051378322, 0.272120993),
        (0.061549512, 0.236151406),
        (0.071302106, 0.204289027),
        (0.080550481, 0.176011212),
        (0.089227357, 0.1509709),
        (0.097151483, 0.129303861),
        (0.104183936, 0.11102652),
        (0.110341629, 0.095819734),
        (0.113128382, 0.089215517),
        (0.115738496, 0.083202675),
        (0.118182545, 0.077730205),
        (0.120464544, 0.072751119),
        (0.122587967, 0.068221918),
        (0.124557872, 0.064102932),
        (0.126380084, 0.060357853),
        (0.12806521, 0.056950567),
        (0.129638308, 0.053837252),
        (0.131124358, 0.050977268),
        (0.132544347, 0.048335457),
        (0.133915997, 0.04588143),
        (0.135248912, 0.04359107),
        (0.136532209, 0.041451621),
        (0.137752788, 0.039453189),
        (0.138900812, 0.037586433),
        (0.139968517, 0.035842464),
        (0.140952976, 0.03421536),
        (0.141862327, 0.03270865),
        (0.14270621, 0.031326817),
        (0.143493342, 0.030073028),
        (0.144231808, 0.028949585),
        (0.144929517, 0.027953136),
        (0.145596337, 0.027061169),
        (0.146871401, 0.025495361),
        (0.148109762, 0.02409121),
        (0.149294066, 0.022816033),
        (0.150364736, 0.021733604),
        (0.151312575, 0.020862901),
        (0.152252746, 0.020081999),
        (0.153291995, 0.019260827),
        (0.154387884, 0.018414805),
        (0.15540432, 0.017674755),
        (0.156278749, 0.017122691),
        (0.15709108, 0.016709427),
        (0.157928892, 0.016366787),
        (0.158785171, 0.0160827),
        (0.159581463, 0.015892612),
        (0.160275124, 0.015823429),
        (0.160927679, 0.015872262),
        (0.161617352, 0.016031261),
        (0.162331252, 0.016268958),
        (0.162957957, 0.016525218),
        (0.163409927, 0.016757637),
        (0.163758875, 0.017018069),
        (0.164122434, 0.017383199),
        (0.16454698, 0.017839402),
        (0.164994968, 0.018272109),
        (0.165419824, 0.018574175),
        (0.165792139, 0.018723341),
        (0.166089132, 0.018722584),
        (0.1662905, 0.018578286),
        (0.166379917, 0.018299802)
    ]
    static let xyRight: [(Double, Double)] = [
        (0.093218329, 0.840634868),
        (0.108493722, 0.837860868),
        (0.124307396, 0.832205673),
        (0.140198493, 0.824632547),
        (0.155817794, 0.815798889),
        (0.17090499, 0.806174854),
        (0.185364306, 0.796087208),
        (0.19958013, 0.785422478),
        (0.213991019, 0.773942797),
        (0.228623268, 0.761716575),
        (0.243156313, 0.749115666),
        (0.257358021, 0.736442234),
        (0.27124628, 0.723763549),
        (0.284889639, 0.711081861),
        (0.298335897, 0.69840766),
        (0.311614271, 0.685757659),
        (0.324812475, 0.673074222),
        (0.338247883, 0.660055239),
        (0.352216419, 0.646418801),
        (0.366525565, 0.632373878),
        (0.380605859, 0.618505495),
        (0.394158043, 0.605124316),
        (0.407630299, 0.591789991),
        (0.421521831, 0.57800948),
        (0.435794845, 0.563825653),
        (0.442933937, 0.556724311),
        (0.450007566, 0.549684489),
        (0.456983652, 0.542738676),
        (0.463877351, 0.535872074),
        (0.470712399, 0.529061271),
        (0.477509187, 0.522286168),
        (0.484285069, 0.515529674),
        (0.491052797, 0.508779294),
        (0.497815994, 0.502031686),
        (0.504575199, 0.495286559),
        (0.511329862, 0.488544668),
        (0.51807818, 0.481807986),
        (0.524805256, 0.475091535),
        (0.531450328, 0.468456123),
        (0.537949995, 0.461965192),
        (0.544250552, 0.455672498),
        (0.550306492, 0.449623606),
        (0.55609666, 0.443839738),
        (0.561666785, 0.438275255),
        (0.567071761, 0.432875346),
        (0.572359445, 0.427592226),
        (0.577570845, 0.422384946),
        (0.582731307, 0.417228213),
        (0.587825003, 0.412137892),
        (0.597722921, 0.402245801),
        (0.607123765, 0.392849743),
        (0.616036566, 0.383940891),
        (0.624568961, 0.375411778),
        (0.632758187, 0.367225292),
        (0.640464948, 0.35952081),
        (0.647561918, 0.35242573),
        (0.654046555, 0.345942663),
        (0.659998796, 0.339991737),
        (0.665484535, 0.334507109),
        (0.670547164, 0.329445418),
        (0.675227828, 0.324772172),
        (0.679581652, 0.320418348),
        (0.683693376, 0.316306624),
        (0.687582753, 0.312417247),
        (0.691109932, 0.308890068),
        (0.694148589, 0.305851411),
        (0.696746634, 0.303253366),
        (0.6990722, 0.3009278),
        (0.701244482, 0.298755518),
        (0.703285547, 0.296714453),
        (0.705198924, 0.294801076),
        (0.707032743, 0.292967257),
        (0.708866844, 0.291133156),
        (0.710708309, 0.289291691),
        (0.712355107, 0.287644893),
        (0.713613015, 0.286386985),
        (0.714517247, 0.285482753),
        (0.715279392, 0.284720608),
        (0.716054852, 0.283945148),
        (0.716849228, 0.283150772),
        (0.71763598, 0.28236402),
        (0.718395912, 0.281604088),
        (0.719116083, 0.280883917),
        (0.719781999, 0.280218001),
        (0.720366876, 0.279633124),
        (0.720844947, 0.279155053),
        (0.721224073, 0.278775927),
        (0.721540928, 0.278459072),
        (0.721824346, 0.278175654),
        (0.722077302, 0.277922698),
        (0.722296914, 0.277703086),
        (0.722484777, 0.277515223),
        (0.722646848, 0.277353152),
        (0.722787641, 0.277212359),
        (0.722906468, 0.277093532),
        (0.723001878, 0.276998122),
        (0.723077863, 0.276922137),
        (0.72314318, 0.27685682),
        (0.723204058, 0.276795942),
        (0.723253465, 0.276746535),
        (0.723281713, 0.276718287),
        (0.723290142, 0.276709858),
        (0.723290807, 0.276709193),
        (0.723293119, 0.276706881),
        (0.723293926, 0.276706074),
        (0.723286857, 0.276713143),
        (0.723266781, 0.276733219),
        (0.723230051, 0.276769949),
        (0.723175196, 0.276824804),
        (0.72311015, 0.27688985),
        (0.72304532, 0.27695468),
        (0.722982798, 0.277017202),
        (0.722917252, 0.277082748),
        (0.722843771, 0.277156229),
        (0.722763819, 0.277236181),
        (0.722679947, 0.277320053),
        (0.72259418, 0.27740582),
        (0.722507438, 0.277492562),
        (0.166379917, 0.018299802)
    ]
    static let uvLeft: [(Double, Double)] = [
        (0.028902261, 0.58643572),
        (0.024408236, 0.584970496),
        (0.020125834, 0.58297214),
        (0.015792505, 0.580439704),
        (0.011474122, 0.577232469),
        (0.007617301, 0.572949681),
        (0.004674906, 0.567084657),
        (0.002730713, 0.55947218),
        (0.001678768, 0.550261816),
        (0.00136311, 0.539656232),
        (0.001657414, 0.527738165),
        (0.002504117, 0.514569733),
        (0.004175287, 0.499948415),
        (0.007067336, 0.483496404),
        (0.011427297, 0.464953098),
        (0.017296696, 0.444299224),
        (0.024654624, 0.421646141),
        (0.033347956, 0.397405491),
        (0.043111576, 0.372170839),
        (0.05372306, 0.346326673),
        (0.065077709, 0.319953577),
        (0.077033094, 0.293261515),
        (0.089184143, 0.267074374),
        (0.101052561, 0.242301336),
        (0.112331195, 0.219481777),
        (0.117709352, 0.208863383),
        (0.122898726, 0.198787629),
        (0.127889438, 0.189257748),
        (0.132667122, 0.180271164),
        (0.137219432, 0.171820199),
        (0.141538234, 0.163893981),
        (0.145618717, 0.156478566),
        (0.149465868, 0.149551727),
        (0.153111422, 0.143067055),
        (0.156590775, 0.136975179),
        (0.159935897, 0.131229988),
        (0.163175623, 0.12578889),
        (0.166327393, 0.120617423),
        (0.169376148, 0.115702083),
        (0.172302298, 0.111033825),
        (0.175090452, 0.106603461),
        (0.177728065, 0.102401432),
        (0.18020769, 0.098424384),
        (0.182531238, 0.094692428),
        (0.18470251, 0.091228117),
        (0.18672543, 0.088050413),
        (0.188604174, 0.085175583),
        (0.190347433, 0.082604409),
        (0.191982004, 0.080285874),
        (0.195035292, 0.076176259),
        (0.197949814, 0.072445689),
        (0.200717736, 0.069018555),
        (0.203190525, 0.066080258),
        (0.205327614, 0.063698552),
        (0.207395009, 0.06154923),
        (0.209662626, 0.059273284),
        (0.212056567, 0.056909943),
        (0.214255595, 0.05482833),
        (0.216084829, 0.053269532),
        (0.217703488, 0.052102425),
        (0.219304285, 0.051136556),
        (0.220886072, 0.050338453),
        (0.222293257, 0.049810585),
        (0.223432054, 0.04963208),
        (0.224397989, 0.049797731),
        (0.225318148, 0.050287307),
        (0.226201117, 0.051007597),
        (0.226930388, 0.051778181),
        (0.227410543, 0.052471979),
        (0.227703865, 0.05324249),
        (0.227919849, 0.054315828),
        (0.228143065, 0.05565192),
        (0.228424012, 0.056917032),
        (0.228792445, 0.057802441),
        (0.229224539, 0.058245589),
        (0.22968304, 0.058255379),
        (0.230131319, 0.057849079),
        (0.230535872, 0.057051427)
    ]
    static let uvRight: [(Double, Double)] = [
        (0.028902261, 0.58643572),
        (0.033805663, 0.587407209),
        (0.039035587, 0.587999476),
        (0.044453854, 0.588313836),
        (0.049949801, 0.58841311),
        (0.055433343, 0.588339611),
        (0.060863395, 0.588129857),
        (0.06638338, 0.587797731),
        (0.072176418, 0.587342141),
        (0.078273174, 0.586770728),
        (0.084553497, 0.586107696),
        (0.090918422, 0.585376637),
        (0.097372095, 0.584588068),
        (0.103943943, 0.583746987),
        (0.110656457, 0.582857997),
        (0.117525282, 0.581925178),
        (0.124601208, 0.580945011),
        (0.132074333, 0.579890692),
        (0.140149483, 0.578733202),
        (0.14876078, 0.577484877),
        (0.157586835, 0.576196403),
        (0.166431218, 0.574898958),
        (0.175585041, 0.573549876),
        (0.185425528, 0.572093392),
        (0.195987973, 0.570525002),
        (0.201452101, 0.56971224),
        (0.20699047, 0.568887689),
        (0.212577805, 0.568055204),
        (0.218225644, 0.567213108),
        (0.223953856, 0.566358465),
        (0.229781189, 0.565488507),
        (0.235725326, 0.564600623),
        (0.24180127, 0.563692603),
        (0.248016741, 0.562763339),
        (0.254377042, 0.561812081),
        (0.260886699, 0.560838188),
        (0.267549178, 0.559841169),
        (0.274354615, 0.558822528),
        (0.281243743, 0.557791161),
        (0.288148302, 0.556757311),
        (0.295003983, 0.555730633),
        (0.301749843, 0.554720275),
        (0.308348011, 0.553731928),
        (0.314836987, 0.552759832),
        (0.321270706, 0.551795909),
        (0.327699784, 0.550832581),
        (0.334170948, 0.549862848),
        (0.340714985, 0.548882102),
        (0.34731143, 0.54789342),
        (0.360535373, 0.545911204),
        (0.373617534, 0.543950033),
        (0.386519557, 0.542015702),
        (0.399353316, 0.540091461),
        (0.412140633, 0.538174063),
        (0.424618596, 0.536302962),
        (0.436510659, 0.534519654),
        (0.447730316, 0.532837131),
        (0.458340196, 0.531246012),
        (0.468394104, 0.529738238),
        (0.477916758, 0.528310107),
        (0.486930526, 0.526960421),
        (0.495515409, 0.525672689),
        (0.50379993, 0.52443001),
        (0.511799805, 0.523230029),
        (0.51919617, 0.522120575),
        (0.525679012, 0.521148148),
        (0.531305213, 0.520304218),
        (0.53640794, 0.519538809),
        (0.541232246, 0.518815163),
        (0.545817019, 0.518127447),
        (0.550161377, 0.517475793),
        (0.554367914, 0.516844813),
        (0.55861766, 0.516207351),
        (0.562927947, 0.515560808),
        (0.566820025, 0.514976996),
        (0.569817129, 0.514527431),
        (0.57198461, 0.514202309),
        (0.573820051, 0.513926992),
        (0.57569564, 0.513645654),
        (0.577625484, 0.513356177),
        (0.579545351, 0.513068197),
        (0.581407892, 0.512788816),
        (0.583180399, 0.51252294),
        (0.584825832, 0.512276125),
        (0.586276173, 0.512058574),
        (0.587465258, 0.511880211),
        (0.588410548, 0.511738418),
        (0.589202148, 0.511619678),
        (0.589911427, 0.511513286),
        (0.590545444, 0.511418183),
        (0.591096632, 0.511335505),
        (0.591568687, 0.511264697),
        (0.591976341, 0.511203549),
        (0.592330782, 0.511150383),
        (0.592630147, 0.511105478),
        (0.592870663, 0.5110694),
        (0.593062307, 0.511040654),
        (0.593227112, 0.511015933),
        (0.593380773, 0.510992884),
        (0.593505519, 0.510974172),
        (0.593576857, 0.510963471),
        (0.593598145, 0.510960278),
        (0.593599826, 0.510960026),
        (0.593605665, 0.51095915),
        (0.593607704, 0.510958844),
        (0.593589849, 0.510961523),
        (0.593539145, 0.510969128),
        (0.593446397, 0.51098304),
        (0.593307916, 0.511003813),
        (0.593143765, 0.511028435),
        (0.59298022, 0.511052967),
        (0.592822555, 0.511076617),
        (0.592657326, 0.511101401),
        (0.592472165, 0.511129175),
        (0.592270789, 0.511159382),
        (0.59205964, 0.511191054),
        (0.591843822, 0.511223427),
        (0.591625663, 0.511256151),
        (0.230535872, 0.057051427),
        (0.230131319, 0.057849079),
        (0.22968304, 0.058255379)
    ]
    static let blackBody: [(Double, Double)] = [
        (0.4696, 0.4173),
        (0.4614, 0.4158),
        (0.4535, 0.4139),
        (0.446, 0.4118),
        (0.4388, 0.4095),
        (0.4254, 0.4044),
        (0.4132, 0.399),
        (0.4021, 0.3934),
        (0.3919, 0.3877),
        (0.3827, 0.382),
        (0.3743, 0.3765),
        (0.3666, 0.3711),
        (0.3596, 0.3659),
        (0.3532, 0.3609),
        (0.3473, 0.3561),
        (0.3419, 0.3516),
        (0.3369, 0.3472),
        (0.3323, 0.3431),
        (0.3281, 0.3392),
        (0.3242, 0.3355),
        (0.3205, 0.3319),
        (0.3171, 0.3286),
        (0.314, 0.3254),
        (0.3083, 0.3195),
        (0.3022, 0.3129),
        (0.297, 0.3071),
        (0.2887, 0.2975),
        (0.2824, 0.2898),
        (0.2734, 0.2785),
        (0.2675, 0.2707),
        (0.2634, 0.265),
        (0.258, 0.2574),
        (0.2516, 0.2481),
        (0.2487, 0.2438)
    ]
}

/// Chromaticity plane of the diagram, with HCFR's chart scale: x from -0.075, y from -0.05,
/// 0.9 × 1.0 wide in xy and 0.8 × 0.8 in u'v', stretched to the whole area.
struct CIEPlane: Equatable {
    var uv: Bool

    var spanX: Double { uv ? 0.8 : 0.9 }
    var spanY: Double { uv ? 0.8 : 1.0 }
    var axisNames: (String, String) { uv ? ("u'", "v'") : ("x", "y") }

    /// xy -> plane coordinates (x, y or u', v').
    func plane(_ x: Double, _ y: Double) -> (Double, Double) {
        guard uv else { return (x, y) }
        let d = -2 * x + 12 * y + 3
        return d == 0 ? (0, 0) : (4 * x / d, 9 * y / d)
    }

    /// Plane coordinates -> xy.
    func xy(_ u: Double, _ v: Double) -> (Double, Double) {
        guard uv else { return (u, v) }
        let d = 6 * u - 16 * v + 12
        return d == 0 ? (0, 0) : (9 * u / d, 4 * v / d)
    }

    /// Plane coordinates -> position in a rectangle (HCFR's bitmap formula).
    func position(_ u: Double, _ v: Double, in r: CGRect) -> CGPoint {
        CGPoint(x: r.minX + (u + 0.075) / spanX * r.width, y: r.minY + (1 - (v + 0.05) / spanY) * r.height)
    }

    func position(xy: (Double, Double), in r: CGRect) -> CGPoint {
        let p = plane(xy.0, xy.1)
        return position(p.0, p.1, in: r)
    }

    var left: [(Double, Double)] { uv ? CIETables.uvLeft : CIETables.xyLeft }
    var right: [(Double, Double)] { uv ? CIETables.uvRight : CIETables.xyRight }
}

/// Wavelength label of the background, in HCFR's 1400 × 1000 bitmap coordinates.
private struct WavelengthLabel {
    let nm: Int
    let lineFrom: CGPoint
    let lineTo: CGPoint
    let text: CGPoint
    let leftSide: Bool
}

@MainActor
private enum CIEBackground {
    static let bitmapSize = CGSize(width: 1400, height: 1000)
    private static var cache: [String: CGImage] = [:]
    private static var labelCache: [Bool: [WavelengthLabel]] = [:]

    /// Labels every 20 nm, placed as HCFR's DrawCIEChart (only on points kept when tracing).
    static func labels(_ plane: CIEPlane) -> [WavelengthLabel] {
        if let l = labelCache[plane.uv] { return l }
        var out: [WavelengthLabel] = []
        func bitmapPoint(_ p: (Double, Double)) -> CGPoint {
            CGPoint(x: Double(Int((p.0 + 0.075) / plane.spanX * 1400)), y: Double(Int((1 - (p.1 + 0.05) / plane.spanY) * 1000)))
        }
        var lastY = -1.0
        for (i, p) in plane.left.enumerated() {
            let b = bitmapPoint(p)
            guard i == 0 || b.y > lastY else { continue }
            lastY = b.y
            if (i * 2) % 20 == 0 && 520 - i * 2 != 520 {
                out.append(WavelengthLabel(nm: 520 - i * 2, lineFrom: b, lineTo: CGPoint(x: b.x - 30, y: b.y + 10),
                                           text: CGPoint(x: b.x - 50, y: b.y + 10), leftSide: true))
            }
        }
        lastY = -1
        for (i, p) in plane.right.enumerated() {
            let b = bitmapPoint(p)
            guard i == 0 || b.y > lastY else { continue }
            lastY = b.y
            if (i * 2) % 20 == 0 {
                out.append(WavelengthLabel(nm: i * 2 + 520, lineFrom: CGPoint(x: b.x + 30, y: b.y - 40), lineTo: b,
                                           text: CGPoint(x: b.x + 30, y: b.y - 50), leftSide: false))
            }
        }
        labelCache[plane.uv] = out
        return out
    }

    /// The colored tongue as HCFR draws it: Rec.709 based colors scaled to the reference white,
    /// a diffusion zone around white, gamma 1/2.2, max 200 (normal) or 255 (lightened, used inside
    /// the measured gamut).
    static func image(width: Int, height: Int, plane: CIEPlane, white: (x: Double, y: Double), light: Bool) -> CGImage? {
        let key = "\(width)x\(height)-\(plane.uv)-\(white.x),\(white.y)-\(light)"
        if let img = cache[key] { return img }
        guard width > 0, height > 0 else { return nil }
        let poly = plane.right + plane.left.reversed()
        let maxVal = light ? 255.0 : 200.0
        let gamma = 1 / 2.2
        let squaredWhiteRay = 0.02
        // xyz -> rgb matrix (Rec.709 primaries), scaled to the reference white
        let (xr, yr) = (0.64, 0.33), (xg, yg) = (0.30, 0.60), (xb, yb) = (0.15, 0.06)
        let (zr, zg, zb) = (1 - xr - yr, 1 - xg - yg, 1 - xb - yb)
        let (xw, yw) = white
        let zw = 1 - xw - yw
        var rx = yg * zb - yb * zg, ry = xb * zg - xg * zb, rz = xg * yb - xb * yg
        var gx = yb * zr - yr * zb, gy = xr * zb - xb * zr, gz = xb * yr - xr * yb
        var bx = yr * zg - yg * zr, by = xg * zr - xr * zg, bz = xr * yg - xg * yr
        let rw = (rx * xw + ry * yw + rz * zw) / yw
        let gw = (gx * xw + gy * yw + gz * zw) / yw
        let bw = (bx * xw + by * yw + bz * zw) / yw
        rx /= rw; ry /= rw; rz /= rw; gx /= gw; gy /= gw; gz /= gw; bx /= bw; by /= bw; bz /= bw

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        // Background RGB(0,10,10)
        for i in stride(from: 0, to: pixels.count, by: 4) { pixels[i + 1] = 10; pixels[i + 2] = 10; pixels[i + 3] = 255 }
        // Scan lines: crossings of the polygon, filled between pairs
        for py in 0..<height {
            let v = (Double(height - py) - 0.5) / Double(height) * plane.spanY - 0.05
            var xs: [Double] = []
            var j = poly.count - 1
            for i in 0..<poly.count {
                let a = poly[i], b = poly[j]
                if (a.1 > v) != (b.1 > v) { xs.append(a.0 + (v - a.1) * (b.0 - a.0) / (b.1 - a.1)) }
                j = i
            }
            xs.sort()
            var k = 0
            while k + 1 < xs.count {
                let p0 = max(0, Int(((xs[k] + 0.075) / plane.spanX * Double(width)).rounded(.up)))
                let p1 = min(width - 1, Int(((xs[k + 1] + 0.075) / plane.spanX * Double(width)).rounded(.down)))
                if p0 <= p1 {
                    for px in p0...p1 {
                        let u = (Double(px) + 0.5) / Double(width) * plane.spanX - 0.075
                        var (x, y) = plane.xy(u, v)
                        let d = (x - xw) * (x - xw) + (y - yw) * (y - yw)
                        if d < squaredWhiteRay {
                            let s = sqrt(d / squaredWhiteRay)
                            x = xw + (x - xw) * s
                            y = yw + (y - yw) * s
                        }
                        let z = 1 - (x + y)
                        var r = rx * x + ry * y + rz * z
                        var g = gx * x + gy * y + gz * z
                        var b = bx * x + by * y + bz * z
                        let lo = min(r, g, b)
                        if lo < 0 { r -= lo; g -= lo; b -= lo }
                        let hi = max(r, g, b)
                        if hi > 0 { r /= hi; g /= hi; b /= hi }
                        let i = (py * width + px) * 4
                        pixels[i] = UInt8(pow(r, gamma) * maxVal)
                        pixels[i + 1] = UInt8(pow(g, gamma) * maxVal)
                        pixels[i + 2] = UInt8(pow(b, gamma) * maxVal)
                    }
                }
                k += 2
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let img = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        if cache.count > 16 { cache.removeAll() }
        cache[key] = img
        return img
    }
}

/// HCFR's CIE diagram (Information → CIE Diagram).
struct CIEChart: View {
    @ObservedObject var session: Session
    /// Smaller version without the options bar (combined views such as Target - CIE).
    var compact = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 4) {
            if !compact {
                HStack(spacing: 12) {
                    Picker("Plane", selection: $session.cieUV) {
                        Text("CIE xy").tag(false)
                        Text("CIE u'v'").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Toggle("Gray scale", isOn: $session.cieShowGrays).toggleStyle(.checkbox)
                    Toggle("References", isOn: $session.cieShowReferences).toggleStyle(.checkbox)
                    Spacer()
                    Text("Reference: \(session.standard.shortName), \(session.white.rawValue)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in chart(size: geo.size) }
        }
    }

    private func chart(size: CGSize) -> some View {
        let plane = CIEPlane(uv: session.cieUV)
        let rect = CGRect(origin: .zero, size: size)
        let wpx = Int(size.width * displayScale), hpx = Int(size.height * displayScale)
        let white = (session.white.x, session.white.y)
        let bg = CIEBackground.image(width: wpx, height: hpx, plane: plane, white: white, light: false)
        let lightBg = CIEBackground.image(width: wpx, height: hpx, plane: plane, white: white, light: true)
        let labels = CIEBackground.labels(plane)
        let patches = Dictionary(uniqueKeysWithValues: session.patchResults.map { ($0.patch, $0) })
        let grays = session.cieShowGrays ? session.results.filter { $0.xyz != nil && $0.level > 0 } : []
        let selectedPatch = session.view == .primariesSecondaries ? session.selectedPatch : nil
        let selectedLevel = session.view == .grayScale ? session.selectedLevel : nil
        let showRefs = session.cieShowReferences
        let sx = size.width / CIEBackground.bitmapSize.width, sy = size.height / CIEBackground.bitmapSize.height
        let small = min(size.width, size.height) < 260
        let penWidth: CGFloat = small ? 2 : 3

        return Canvas { ctx, _ in
            func pos(_ xy: (Double, Double)) -> CGPoint { plane.position(xy: xy, in: rect) }
            func bmp(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * sx, y: p.y * sy) }

            // Background tongue
            if let bg { ctx.draw(Image(decorative: bg, scale: displayScale), in: rect) }
            else { ctx.fill(Path(rect), with: .color(Color(red: 0, green: 10 / 255, blue: 10 / 255))) }

            // Axes (HCFR: lines RGB 64, labels every 0.1)
            var axes = Path()
            let nx = plane.uv ? 7 : 8, ny = plane.uv ? 7 : 9
            let axisFont = Font.system(size: max(8, min(11, 14 * sy)))
            for i in 0..<nx {
                let x = rect.width * (Double(i) + 0.75) / (plane.uv ? 8 : 9)
                axes.move(to: CGPoint(x: x, y: 0)); axes.addLine(to: CGPoint(x: x, y: rect.height))
                if i > 0 && !small {
                    ctx.draw(Text(String(format: "%.1f", Double(i) / 10)).font(axisFont).foregroundColor(.white),
                             at: CGPoint(x: x + 2, y: rect.height), anchor: .bottomLeading)
                }
            }
            for i in 0..<ny {
                let y = rect.height * (Double(i) + 0.5) / (plane.uv ? 8 : 10)
                axes.move(to: CGPoint(x: 0, y: y)); axes.addLine(to: CGPoint(x: rect.width, y: y))
                if i > 0 && !small {
                    ctx.draw(Text(String(format: "%.1f", (plane.uv ? 0.7 : 0.9) - Double(i) / 10)).font(axisFont).foregroundColor(.white),
                             at: CGPoint(x: 2, y: y), anchor: .bottomLeading)
                }
            }
            ctx.stroke(axes, with: .color(Color(white: 64 / 255)), lineWidth: 1)

            // Black body curve (drawn again in black inside the lightened gamut, as in HCFR's light chart)
            var bb = Path()
            for (i, p) in CIETables.blackBody.enumerated() {
                let q = pos(p)
                i == 0 ? bb.move(to: q) : bb.addLine(to: q)
            }
            let bbWidth = max(1, 2 * sx)
            ctx.stroke(bb, with: .color(Color(white: 180 / 255)), lineWidth: bbWidth)

            // Wavelength labels
            if !small {
                let wlColor = Color(red: 220 / 255, green: 220 / 255, blue: 1)
                let wlFont = Font.system(size: max(8, 24 * sy * 0.62), design: .serif)
                var leaders = Path()
                for l in labels {
                    leaders.move(to: bmp(l.lineFrom)); leaders.addLine(to: bmp(l.lineTo))
                    ctx.draw(Text("\(l.nm) nm").font(wlFont).foregroundColor(wlColor), at: bmp(l.text),
                             anchor: l.leftSide ? .top : .topLeading)
                }
                ctx.stroke(leaders, with: .color(wlColor), lineWidth: 1)
            }

            // Measured gamut, filled with the lightened chart (primaries, and secondaries when measured)
            func m(_ p: PatchColor) -> CGPoint? {
                guard let x = patches[p]?.xyz, x.Y > 0 else { return nil }
                return pos((x.x, x.y))
            }
            let measuredGamut: [CGPoint]? = {
                guard let r = m(.red), let g = m(.green), let b = m(.blue) else { return nil }
                if let yl = m(.yellow), let c = m(.cyan), let mg = m(.magenta) { return [r, yl, g, c, b, mg] }
                return [r, g, b]
            }()
            if let measuredGamut, let lightBg {
                var gamut = Path()
                gamut.addLines(measuredGamut); gamut.closeSubpath()
                ctx.drawLayer { layer in
                    layer.clip(to: gamut)
                    layer.draw(Image(decorative: lightBg, scale: displayScale), in: rect)
                    layer.stroke(bb, with: .color(.black), lineWidth: bbWidth)
                }
            }

            // Reference gamut: R-Y-G-C-B-M hexagon, gray pen masking the chart (HCFR's R2_MASKPEN)
            let refOrder: [PatchColor] = [.red, .yellow, .green, .cyan, .blue, .magenta]
            var refHex = Path()
            refHex.addLines(refOrder.compactMap { patches[$0].map { pos(($0.reference.x, $0.reference.y)) } })
            refHex.closeSubpath()
            ctx.drawLayer { layer in
                layer.blendMode = .multiply
                layer.stroke(refHex, with: .color(Color(white: 128 / 255)), lineWidth: penWidth)
            }

            // Measured gamut outline
            if let measuredGamut {
                var g = Path()
                g.addLines(measuredGamut); g.closeSubpath()
                ctx.stroke(g, with: .color(.white.opacity(0.85)), lineWidth: penWidth - 1)
            }

            // White reference dotted cross
            if !small {
                let w = pos(white)
                var cross = Path()
                cross.move(to: CGPoint(x: 5, y: w.y)); cross.addLine(to: CGPoint(x: rect.width - 5, y: w.y))
                cross.move(to: CGPoint(x: w.x, y: 5)); cross.addLine(to: CGPoint(x: w.x, y: rect.height - 5))
                ctx.stroke(cross, with: .color(Color(white: 192 / 255)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }

            // Illuminants and color temperatures
            if showRefs && !small {
                let refFont = Font.system(size: max(8, min(11, 16 * sy)))
                func refPoint(_ xy: (Double, Double), _ label: String, _ anchor: UnitPoint, _ dx: CGFloat, _ dy: CGFloat, filled: Bool) {
                    let p = pos(xy)
                    let dot = Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
                    ctx.fill(dot, with: .color(filled ? Color(red: 0.3, green: 0.8, blue: 0.3) : .white))
                    ctx.stroke(dot, with: .color(.black), lineWidth: 1)
                    ctx.draw(Text(label).font(refFont).foregroundColor(.black), at: CGPoint(x: p.x + dx, y: p.y + dy), anchor: anchor)
                }
                refPoint((0.4476, 0.4074), "A", .top, -2, 4, filled: true)
                refPoint((0.3484, 0.3516), "B", .topLeading, 4, 4, filled: true)
                refPoint((0.3101, 0.3162), "C", .topLeading, 4, 4, filled: true)
                refPoint((0.3127, 0.3291), "D65", .bottomTrailing, -4, -4, filled: true)
                refPoint((0.2866, 0.2950), "9300", .bottomTrailing, -2, -2, filled: false)
                refPoint((0.3827, 0.3820), "4000", .bottomTrailing, -2, -2, filled: false)
                refPoint((0.3346, 0.3451), "5500", .bottomTrailing, -2, -2, filled: false)
                refPoint((0.4388, 0.4095), "3000", .bottomTrailing, 2, -2, filled: false)
                refPoint((0.4614, 0.4158), "2700", .bottomLeading, -2, -2, filled: false)
            }

            // Lines primary -> opposite secondary (measured)
            if let r = m(.red), let g = m(.green), let b = m(.blue), let c = m(.cyan), let mg = m(.magenta), let yl = m(.yellow) {
                var l = Path()
                l.move(to: r); l.addLine(to: c)
                l.move(to: g); l.addLine(to: mg)
                l.move(to: b); l.addLine(to: yl)
                ctx.stroke(l, with: .color(Color(white: 64 / 255)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }

            // Gray scale points
            for gr in grays {
                guard let xyz = gr.xyz, xyz.Y > 0 else { continue }
                let p = pos((xyz.x, xyz.y))
                let sel = gr.level == selectedLevel
                let r: CGFloat = sel ? 4.5 : 3
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                ctx.fill(dot, with: .color(.white))
                ctx.stroke(dot, with: .color(sel ? .orange : .black), lineWidth: sel ? 2 : 1)
            }

            // Reference markers (square with a dot) and measured markers (colored square)
            let side: CGFloat = small ? 7 : 10
            for p in PatchColor.allCases where p != .white {
                guard let pr = patches[p] else { continue }
                let c = pos((pr.reference.x, pr.reference.y))
                let sq = Path(CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side))
                ctx.stroke(sq, with: .color(Self.markerColor(p)), lineWidth: 1.5)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)), with: .color(.white))
            }
            for p in PatchColor.allCases {
                guard let c = m(p), p != .white || session.view == .primariesSecondaries else { continue }
                let sel = p == selectedPatch
                let s = side + 2
                let sq = Path(CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s))
                ctx.stroke(sq, with: .color(.black), lineWidth: 3.5)
                ctx.stroke(sq, with: .color(Self.markerColor(p)), lineWidth: 2)
                if sel {
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - s, y: c.y - s, width: 2 * s, height: 2 * s)), with: .color(.orange), lineWidth: 2)
                }
            }

            // Axis names
            if !small {
                ctx.draw(Text(plane.axisNames.0).font(.caption.bold()).foregroundColor(.white),
                         at: CGPoint(x: rect.width - 6, y: rect.height - 16), anchor: .bottomTrailing)
                ctx.draw(Text(plane.axisNames.1).font(.caption.bold()).foregroundColor(.white),
                         at: CGPoint(x: 28, y: 4), anchor: .topLeading)
            }
        }
        .clipShape(Rectangle())
    }

    static func markerColor(_ p: PatchColor) -> Color {
        switch p {
        case .red: return Color(red: 1, green: 0.15, blue: 0.15)
        case .green: return Color(red: 0.15, green: 0.85, blue: 0.15)
        case .blue: return Color(red: 0.3, green: 0.3, blue: 1)
        case .yellow: return Color(red: 1, green: 0.85, blue: 0)
        case .cyan: return Color(red: 0, green: 0.85, blue: 0.95)
        case .magenta: return Color(red: 1, green: 0.2, blue: 1)
        case .white: return .white
        }
    }
}

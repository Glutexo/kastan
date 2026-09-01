import Foundation
import Testing
@testable import Kastan

/// Verifies the shared product meanings independently of any one human-readable interface.
@Test func serviceInformationRecognizesPassengerFacingMeanings() {
    let examples: [(String, IDOSServiceInformation.Category)] = [
        ("Replacement bus service", .replacementBus),
        ("Na lince platí tarif a přepravní podmínky vyhlášené dopravcem.", .fareConditions),
        ("Tickets of the integrated transport system are also valid.", .integratedTransportTicket),
        ("Jízdenky možno zakoupit předem na webu dopravce.", .ticketPurchase),
        ("Cancellation policy applies.", .cancellationPolicy),
        ("Telefonické rezervace neprovádíme.", .phoneReservation),
        ("Vnitrostátní přeprava je povolena.", .domesticTransport),
        ("Nedoprovázená zavazadla a živá zvířata se nepřepravují.", .carriageRestriction),
        ("Přeprava jednoho zavazadla zdarma.", .baggage),
        ("Osoby podnapilé mohou být vyloučeny z přepravy.", .passengerWarning),
        ("V lůžkovém voze jsou oddíly Deluxe se sprchou.", .deluxeCompartment),
        ("Lůžkový vůz", .sleepingCar),
        ("Couchette coach", .couchetteCar),
        ("Vlak veze přímý vůz do Berlína.", .throughCoach),
        ("Ze stanice Děčín hl.n. vlak LE 235.", .trainDesignationChange),
        ("Ve vlaku řazeny k sezení i vozy 1. vozové třídy.", .firstClassSeating),
        ("vozy 1. a 2. třídy", .firstClassSeating),
        ("1st and 2nd class coaches", .firstClassSeating),
        ("Train also consists of 1st class coaches", .firstClassSeating),
        ("Ve vlaku řazeny k sezení pouze vozy 2. vozové třídy.", .secondClassOnly),
        ("Samoobslužný způsob odbavování cestujících.", .selfServiceCheckIn),
        ("Bistro car", .diningCar),
        ("Refreshment trolley service", .refreshment),
        ("Mobile snack-bar", .refreshment),
        ("All information on https://example.com", .webInformation),
        ("Palubní portál", .onboardPortal),
        ("Ve vlaku je bezdrátové připojení k internetu.", .wiFi),
        ("Power socket available.", .powerSocket),
        ("Tichý oddíl", .quietCompartment),
        ("Dětské kino", .childrenCinema),
        ("Children's theater", .childrenCinema),
        ("Vůz pro cestující s dětmi.", .familyCompartment),
        ("Ladies compartment for women travelling alone.", .womenCompartment),
        ("Bicycle transport is not permitted.", .bicycleUnavailable),
        ("Přeprava jízdních kol jako spoluzavazadel.", .bicycle),
        ("Carriage of registered luggage (until full capacity)", .bicycle),
        ("Vůz vhodný pro přepravu cestujících na vozíku.", .wheelchair),
        ("Bezbariérový spoj", .wheelchair),
        ("Spoj s bezbariérově přístupným vozidlem.", .wheelchair),
        ("Spoj je obsluhován nízkopodlažním vozidlem.", .wheelchair),
        ("The service is operated by a low-floor vehicle.", .wheelchair),
        ("Seat reservation available.", .seatReservation),
        ("Reservations possible in indicated coaches", .seatReservation),
        ("Compulsory reservation", .seatReservation),
        ("Vlak nečeká na přípoje.", .connectionWait),
        ("Vlak je provozován na komerční riziko dopravce.", .commercialOperation),
        ("Pohraniční přechodový bod [CZ/A]: Břeclav(Gr).", .borderCrossing),
        ("Na trase je plánované omezení provozu.", .trafficRestriction),
        ("Jede v 1-5.", .operatingCalendar),
        ("MÁV; Könyves Kálmán körút 36., 1097 Budapest", .carrier),
        ("Háje - Letňany", .route),
        (
            "A: vynechá zastávky Místek,Frýdlantská, Místek,Riviéra a Místek,Beskydská",
            .route
        ),
        ("A: skips the following stops: Central Park and Riverside", .route),
        ("Doplňující informace", .general),
    ]

    for (text, category) in examples {
        let information = IDOSServiceInformation(text: text)

        #expect(information.text == text)
        #expect(information.category == category, Comment(rawValue: text))
        #expect(information.displayText == "\(category.symbol) \(text)")
    }
}

/// Protects precedence rules where broad words, company forms, and place names could hide the real meaning.
@Test func serviceInformationAvoidsKnownFalsePositives() {
    let examples: [(String, IDOSServiceInformation.Category)] = [
        ("Na lince platí tarif vyhlášený A-EXPRESS s.r.o. Plzeň.", .fareConditions),
        ("Places reservation required. There is a valid tariff set by the carrier.", .seatReservation),
        ("Platí také jízdní doklady IREDO (Kolín→Březová n.Svitavou).", .integratedTransportTicket),
        ("Jízdní doklady se prodávají ve vlaku.", .general),
        ("Tarifní zóna 101", .general),
        ("Doplňující informace; bez omezení", .general),
        ("K-IM Tour Michalovce", .general),
    ]

    for (text, category) in examples {
        #expect(
            IDOSServiceInformation(text: text).category == category,
            Comment(rawValue: text)
        )
    }
}

/// Makes diagnostics report the successful classifier predicates rather than only their category outcome.
@Test func serviceInformationExposesItsConcreteClassificationRule() {
    #expect(
        IDOSServiceInformation(text: "Bezbariérový spoj").classificationRule ==
            .contains("bezbarierovy spoj")
    )
    #expect(
        IDOSServiceInformation(
            text: "Spoj je obsluhován nízkopodlažním vozidlem."
        ).classificationRule == .all([
            .contains("nizkopodlazn"),
            .contains("vozidl"),
        ])
    )
    #expect(
        IDOSServiceInformation(
            text: "Na lince platí tarif a přepravní podmínky vyhlášené dopravcem."
        ).classificationRule == .all([
            .contains("tarif"),
            .contains("prepravni podmink"),
        ])
    )
    #expect(
        IDOSServiceInformation(text: "Doplňující informace").classificationRule == .fallback
    )
}

/// Lets the app supply a parsed calendar meaning only as a fallback behind more specific passenger services.
@Test func serviceInformationUsesAnExplicitFallbackWithoutOverridingSpecificMeaning() {
    #expect(
        IDOSServiceInformation(
            text: "v 1-5,7",
            fallbackCategory: .operatingCalendar
        ).category == .operatingCalendar
    )
    #expect(
        IDOSServiceInformation(
            text: "Dámský oddíl v 1-5,7",
            fallbackCategory: .operatingCalendar
        ).category == .womenCompartment
    )
    #expect(
        IDOSServiceInformation(
            text: "Linka 154 v 1-5,7",
            fallbackCategory: .operatingCalendar
        ).category == .operatingCalendar
    )
}

/// Lets a structured provider preserve its own category even when IDOS's text classifier would choose another.
@Test func serviceInformationAcceptsAnExactProviderCategory() throws {
    let information = TransitServiceInformation(
        text: "Provider accessibility code W",
        category: .wheelchair
    )

    #expect(information.category == .wheelchair)
    #expect(information.classificationRule == .fallback)
    #expect(
        try JSONDecoder().decode(
            TransitServiceInformation.self,
            from: JSONEncoder().encode(information)
        ) == information
    )
}

/// Makes classified information discoverable directly from the service model without changing its raw payload.
@Test func serviceDetailExposesClassifiedInformationInIDOSOrder() {
    var service = IDOSServiceDetail(
        id: "vlaky:service",
        name: "R 1",
        stops: [],
        information: ["Bistro car", "Doplňující informace"]
    )

    #expect(service.information == ["Bistro car", "Doplňující informace"])
    #expect(service.serviceInformation.map(\.text) == service.information)
    #expect(service.serviceInformation.map(\.category) == [.diningCar, .general])

    service.information = ["Carriage with a wireless internet connection"]
    #expect(service.serviceInformation.map(\.category) == [.wiFi])
}

/// Lets a structured provider attach semantic service-detail categories without imitating IDOS wording.
@Test func serviceDetailPreservesStructuredProviderInformationAndLegacyJSON() throws {
    let structured = TransitServiceDetail(
        id: "municipal:accessible",
        timetable: TransitTimetable(
            dataSourceID: "municipal",
            identifier: "metro",
            displayName: "Metro"
        ),
        name: "M1",
        stops: [],
        serviceInformation: [
            TransitServiceInformation(
                text: "Provider accessibility code W",
                category: .wheelchair
            ),
        ]
    )
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let structuredData = try encoder.encode(structured)
    let structuredObject = try #require(
        JSONSerialization.jsonObject(with: structuredData) as? [String: Any]
    )

    #expect(structured.information == ["Provider accessibility code W"])
    #expect(structured.serviceInformation.map(\.category) == [.wheelchair])
    #expect(structuredObject["information"] != nil)
    #expect(structuredObject["serviceInformation"] != nil)
    #expect(try decoder.decode(TransitServiceDetail.self, from: structuredData) == structured)

    let legacy = TransitServiceDetail(
        id: "vlaky:legacy",
        name: "R 1",
        stops: [],
        information: ["Bistro car"]
    )
    let legacyData = try encoder.encode(legacy)
    let legacyObject = try #require(JSONSerialization.jsonObject(with: legacyData) as? [String: Any])
    #expect(legacyObject["serviceInformation"] == nil)
    #expect(try decoder.decode(TransitServiceDetail.self, from: legacyData) == legacy)
}

/// Retains source compatibility for stored result JSON while preserving newly parsed information.
@Test func resultServiceInformationRoundTripsAndDefaultsWhenAbsent() throws {
    let information = [IDOSServiceInformation(text: "Carriage with a wireless internet connection")]
    let leg = IDOSConnectionLeg(
        name: "S6 (Os 3133)",
        departureTime: "17:37",
        fromStation: "Valašské Meziříčí",
        arrivalTime: "18:10",
        toStation: "Frenštát p.Radhoštěm",
        serviceInformation: information
    )
    let departure = IDOSDeparture(
        id: "vlaky:0-1-04.08.2026 17:37:00",
        time: "17:37",
        lineName: "S6 (Os 3133)",
        destination: "Ostrava hl.n.",
        serviceInformation: information
    )
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    #expect(try decoder.decode(IDOSConnectionLeg.self, from: encoder.encode(leg)) == leg)
    #expect(try decoder.decode(IDOSDeparture.self, from: encoder.encode(departure)) == departure)

    let legacyLeg = try decoder.decode(
        IDOSConnectionLeg.self,
        from: Data(
            #"{"name":"S6","departureTime":"17:37","fromStation":"A","arrivalTime":"18:10","toStation":"B"}"#.utf8
        )
    )
    let legacyDeparture = try decoder.decode(
        IDOSDeparture.self,
        from: Data(#"{"id":"service","time":"17:37","lineName":"S6","destination":"B"}"#.utf8)
    )

    #expect(legacyLeg.serviceInformation.isEmpty)
    #expect(legacyDeparture.serviceInformation.isEmpty)
}

/// Keeps every public category paired with the stable visual marker used by the CLI and macOS app.
@Test func everyServiceInformationCategoryHasItsProductSymbol() {
    let expected: [(IDOSServiceInformation.Category, String)] = [
        (.replacementBus, "🚌"),
        (.fareConditions, "🎫"),
        (.integratedTransportTicket, "🎟️"),
        (.ticketPurchase, "🎫"),
        (.cancellationPolicy, "↩️"),
        (.phoneReservation, "📵"),
        (.domesticTransport, "✅"),
        (.carriageRestriction, "🚫"),
        (.baggage, "🧳"),
        (.passengerWarning, "⚠️"),
        (.deluxeCompartment, "🚿"),
        (.sleepingCar, "🛏️"),
        (.couchetteCar, "🛌"),
        (.throughCoach, "➡️"),
        (.trainDesignationChange, "🔄"),
        (.firstClassSeating, "1️⃣"),
        (.secondClassOnly, "2️⃣"),
        (.selfServiceCheckIn, "👁️"),
        (.diningCar, "🍽️"),
        (.refreshment, "🥤"),
        (.webInformation, "🌐"),
        (.onboardPortal, "🌐"),
        (.wiFi, "🛜"),
        (.powerSocket, "🔌"),
        (.quietCompartment, "🤫"),
        (.childrenCinema, "📽️"),
        (.familyCompartment, "👶🏻"),
        (.womenCompartment, "👩🏻"),
        (.bicycleUnavailable, "🚳"),
        (.bicycle, "🚲"),
        (.wheelchair, "♿"),
        (.seatReservation, "💺"),
        (.connectionWait, "⏱️"),
        (.commercialOperation, "💼"),
        (.borderCrossing, "🛂"),
        (.trafficRestriction, "🚧"),
        (.operatingCalendar, "📅"),
        (.carrier, "🏢"),
        (.route, "🛤️"),
        (.general, "ℹ️"),
    ]

    #expect(expected.map(\.0) == IDOSServiceInformation.Category.allCases)
    for (category, symbol) in expected {
        #expect(category.symbol == symbol)
    }
}

import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import ResetCore

struct PlacesView: View {
    @Environment(\.modelContext) private var context
    @Environment(LocationTracker.self) private var tracker
    @Query(sort: \Place.createdAt) private var places: [Place]
    @State private var editing: Place?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                PermissionCard()
            }
            Section("Saved places") {
                if places.isEmpty {
                    EmptyNote(systemImage: "mappin.and.ellipse", title: "No places yet",
                              message: "Add your workplace or university to get arrival and departure suggestions.",
                              actionTitle: "Add a place") { adding = true }
                }
                ForEach(places) { p in
                    Button { editing = p } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.name).font(.headline)
                                Text("\(p.category.rawValue.capitalized), \(Int(p.radiusM)) m radius\(p.enabled ? "" : ", off")")
                                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { idx in
                    idx.map { places[$0] }.forEach(context.delete)
                    try? context.save()
                    Task { await tracker.start(context: context) }
                }
            }
        }
        .navigationTitle("Places")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add place") }
        .sheet(isPresented: $adding) { PlaceEditor(place: nil) }
        .sheet(item: $editing) { PlaceEditor(place: $0) }
    }
}

struct PermissionCard: View {
    @Environment(LocationTracker.self) private var tracker

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(statusTitle, systemImage: tracker.isAlways ? "checkmark.circle.fill" : "location.slash")
                .font(.headline)
            Text("RE:SET uses region monitoring, which is battery friendly and does not track your route. iOS decides when to deliver arrival and departure events, so they can be late or missed. Treat times as estimates and correct them when needed. Being at a place does not prove you were working.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            if !tracker.servicesEnabled {
                Text("Location Services are off. Turn them on in Settings > Privacy & Security.").font(.footnote)
            } else if tracker.isDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } else if !tracker.isAlways {
                Button(tracker.authorization == .notDetermined ? "Allow location" : "Allow \"Always\" for background arrivals") {
                    tracker.authorization == .notDetermined ? tracker.requestWhenInUse() : tracker.requestAlways()
                }
            }
        }
    }

    private var statusTitle: String {
        if tracker.isAlways { return "Background arrivals on" }
        if tracker.isDenied { return "Location permission required" }
        if tracker.authorization == .authorizedWhenInUse { return "Only while the app is open" }
        return "Location not enabled"
    }
}

struct PlaceEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationTracker.self) private var tracker

    let place: Place?
    @State private var name = ""
    @State private var category: SessionCategory = .work
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var radius = 150.0
    @State private var enabled = true
    @State private var remind = false
    @State private var tolerance = 20
    @State private var useSchedule = false
    @State private var startMin = 9 * 60
    @State private var endMin = 17 * 60
    @State private var camera: MapCameraPosition = .automatic
    @State private var error: String?
    @State private var query = ""
    @State private var found: [MKMapItem] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Search a name, e.g. Anytime Fitness", text: $query).submitLabel(.search).onSubmit(search)
                        Button("Search", action: search).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(found, id: \.self) { item in
                        Button { pick(item) } label: {
                            VStack(alignment: .leading) {
                                Text(item.name ?? "Place")
                                if let a = item.placemark.title { Text(a).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1) }
                            }
                        }.buttonStyle(.plain)
                    }
                } header: { Text("Find it") }
                Section("Place") {
                    TextField("Name", text: $name)
                    Picker("Tracks", selection: $category) {
                        Text("Work").tag(SessionCategory.work)
                        Text("University").tag(SessionCategory.university)
                        Text("Gym").tag(SessionCategory.gym)
                        Text("Home or other").tag(SessionCategory.other)
                    }
                    Toggle("Enabled", isOn: $enabled)
                }
                Section {
                    MapReader { proxy in
                        Map(position: $camera) {
                            if let c = coordinate {
                                Marker(name.isEmpty ? "Place" : name, coordinate: c)
                                MapCircle(center: c, radius: radius).foregroundStyle(Theme.accent.opacity(0.25))
                            }
                            UserAnnotation()
                        }
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { point in
                            if let c = proxy.convert(point, from: .local) { coordinate = c }
                        }
                    }
                    Button("Use my current location") {
                        Task {
                            do {
                                let c = try await tracker.currentCoordinate()
                                coordinate = c
                                camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: 800, longitudinalMeters: 800))
                            } catch { self.error = "Could not get your location. Check permission or tap the map instead." }
                        }
                    }
                    Slider(value: $radius, in: 100...500, step: 25) { Text("Radius") }
                    Text("Radius: \(Int(radius)) m. Larger is more reliable, smaller is more precise.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                    if let error { Text(error).foregroundStyle(Theme.low).font(.footnote) }
                } header: { Text("Location. Tap the map to place the pin.") }
                Section("Schedule and breaks") {
                    Toggle("Expected hours", isOn: $useSchedule)
                    if useSchedule {
                        DatePicker("From", selection: $startMin.asTimeOfDay(), displayedComponents: .hourAndMinute)
                        DatePicker("To", selection: $endMin.asTimeOfDay(), displayedComponents: .hourAndMinute)
                    }
                    Toggle("Remind me on arrival", isOn: $remind)
                }
            }
            .navigationTitle(place == nil ? "New place" : "Edit place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || coordinate == nil)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func search() {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        if let c = coordinate { req.region = MKCoordinateRegion(center: c, latitudinalMeters: 20_000, longitudinalMeters: 20_000) }
        Task {
            found = (try? await MKLocalSearch(request: req).start().mapItems.prefix(5).map { $0 }) ?? []
            if found.isEmpty { error = "Nothing found. Try the map instead." }
        }
    }

    private func pick(_ item: MKMapItem) {
        let c = item.placemark.coordinate
        coordinate = c
        if name.isEmpty { name = item.name ?? query }
        camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: 800, longitudinalMeters: 800))
        found = []; error = nil
    }

    private func load() {
        guard let p = place else { return }
        name = p.name; category = p.category; radius = p.radiusM; enabled = p.enabled
        remind = p.remindOnArrival; tolerance = p.breakToleranceMin
        coordinate = CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
        if let s = p.expectedStartMinute, let e = p.expectedEndMinute { useSchedule = true; startMin = s; endMin = e }
        camera = .region(MKCoordinateRegion(center: coordinate!, latitudinalMeters: 800, longitudinalMeters: 800))
    }

    private func save() {
        guard let c = coordinate else { return }
        let p = place ?? Place(name: name, category: category, latitude: c.latitude, longitude: c.longitude)
        p.name = name.trimmingCharacters(in: .whitespaces); p.category = category
        p.latitude = c.latitude; p.longitude = c.longitude; p.radiusM = radius; p.enabled = enabled
        p.remindOnArrival = remind; p.breakToleranceMin = tolerance
        p.expectedStartMinute = useSchedule ? startMin : nil
        p.expectedEndMinute = useSchedule ? endMin : nil
        if place == nil { context.insert(p) }
        try? context.save()
        if tracker.authorization == .notDetermined { tracker.requestWhenInUse() }
        else if tracker.authorization == .authorizedWhenInUse { tracker.requestAlways() }
        Task { await tracker.start(context: context) }
        dismiss()
    }
}

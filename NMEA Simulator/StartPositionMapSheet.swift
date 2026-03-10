//
//  StartPositionMapSheet.swift
//  NMEA Simulator
//
//  Created by Jip van Akker on 10/03/2026.
//

import SwiftUI
import MapKit

struct StartPositionMapSheet: View {
    let defaultCoordinate: CLLocationCoordinate2D
    let onApply: (CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCoordinate: CLLocationCoordinate2D
    @State private var cameraPosition: MapCameraPosition

    init(
        initialCoordinate: CLLocationCoordinate2D,
        defaultCoordinate: CLLocationCoordinate2D,
        onApply: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        self.defaultCoordinate = defaultCoordinate
        self.onApply = onApply
        _selectedCoordinate = State(initialValue: initialCoordinate)
        _cameraPosition = State(initialValue: .region(Self.region(center: initialCoordinate)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Click on the map to set the GPS starting position.")
                .font(.headline)

            MapReader { proxy in
                Map(position: $cameraPosition) {
                    Marker("Start", coordinate: selectedCoordinate)
                        .tint(.red)
                }
                .mapStyle(.standard(elevation: .realistic))
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard let coordinate = proxy.convert(value.location, from: .local) else {
                                return
                            }
                            selectedCoordinate = coordinate
                        }
                )
            }
            .frame(minWidth: 740, minHeight: 460)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text("Latitude: \(selectedCoordinate.latitude, specifier: "%.6f")")
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Text("Longitude: \(selectedCoordinate.longitude, specifier: "%.6f")")
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Button("Reset To Default") {
                    selectedCoordinate = defaultCoordinate
                    cameraPosition = .region(Self.region(center: defaultCoordinate))
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Use Position") {
                    onApply(selectedCoordinate)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private static func region(center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    }
}

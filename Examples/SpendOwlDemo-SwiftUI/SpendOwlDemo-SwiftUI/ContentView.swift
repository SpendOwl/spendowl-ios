import SwiftUI
import SpendOwl

struct ContentView: View {
    @State private var attribution: AttributionResult?
    @State private var error: SpendOwlError?
    @State private var isLoading = false
    @State private var userId = ""

    var body: some View {
        NavigationStack {
            List {
                // Attribution Section
                Section {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Fetching attribution...")
                                .foregroundStyle(.secondary)
                        }
                    } else if let attribution {
                        AttributionRow(title: "Status", value: attribution.status.displayName)
                        AttributionRow(title: "Campaign", value: attribution.campaignName ?? "-")
                        AttributionRow(title: "Campaign ID", value: attribution.campaignId.map(String.init) ?? "-")
                        AttributionRow(title: "Ad Group", value: attribution.adGroupName ?? "-")
                        AttributionRow(title: "Keyword", value: attribution.keyword ?? "-")
                        AttributionRow(title: "Country", value: attribution.countryOrRegion ?? "-")
                        AttributionRow(title: "Conversion", value: attribution.conversionType ?? "-")
                    } else if let error {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Error")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(error.localizedDescription)
                                .foregroundStyle(.red)
                        }
                    } else {
                        Text("Tap 'Fetch Attribution' to start")
                            .foregroundStyle(.secondary)
                    }

                    Button("Fetch Attribution") {
                        fetchAttribution()
                    }
                    .disabled(isLoading)
                } header: {
                    Text("Attribution")
                } footer: {
                    Text("Attribution data from Apple Ads via SpendOwl backend.")
                }

                // User ID Section
                Section {
                    TextField("User ID", text: $userId)
                        .textContentType(.username)
                        .autocapitalization(.none)

                    Button("Set User ID") {
                        guard !userId.isEmpty else { return }
                        SpendOwl.setUserId(userId)
                    }
                    .disabled(userId.isEmpty)

                    Button("Clear User ID", role: .destructive) {
                        SpendOwl.clearUserId()
                        userId = ""
                    }
                } header: {
                    Text("User Identity")
                } footer: {
                    Text("Set a user ID to link attribution with your user accounts.")
                }

                // Purchase Tracking Section
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Automatic")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Purchase Tracking")
                } footer: {
                    Text("StoreKit 2 purchases are tracked automatically for ROAS calculation. Works alongside RevenueCat or Adapty.")
                }

                // Debug Section
                Section {
                    Toggle("Enable Logging", isOn: Binding(
                        get: { SpendOwl.enableLogging },
                        set: { SpendOwl.enableLogging = $0 }
                    ))

                    HStack {
                        Text("SDK Version")
                        Spacer()
                        Text(SpendOwl.sdkVersion)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Configured")
                        Spacer()
                        Image(systemName: SpendOwl.isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(SpendOwl.isConfigured ? .green : .red)
                    }
                } header: {
                    Text("Debug")
                }
            }
            .navigationTitle("SpendOwl Demo")
        }
    }

    private func fetchAttribution() {
        isLoading = true
        error = nil

        Task {
            do {
                attribution = try await SpendOwl.attribution()
            } catch let err as SpendOwlError {
                error = err
            } catch {
                self.error = .unknown(error)
            }
            isLoading = false
        }
    }
}

struct AttributionRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

extension AttributionStatus {
    var displayName: String {
        switch self {
        case .attributed: return "Attributed"
        case .organic: return "Organic"
        case .unknown: return "Unknown"
        }
    }
}

#Preview {
    ContentView()
}

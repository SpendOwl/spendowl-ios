import UIKit
import SpendOwl

class AttributionViewController: UITableViewController {

    // MARK: - Properties

    private var attribution: AttributionResult?
    private var error: SpendOwlError?
    private var isLoading = false
    private var userId: String = ""

    private enum Section: Int, CaseIterable {
        case attribution
        case userIdentity
        case purchases
        case debug
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        title = "SpendOwl Demo"
        navigationController?.navigationBar.prefersLargeTitles = true

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(TextFieldCell.self, forCellReuseIdentifier: "TextFieldCell")
        tableView.register(SwitchCell.self, forCellReuseIdentifier: "SwitchCell")
    }

    // MARK: - Actions

    private func fetchAttribution() {
        isLoading = true
        error = nil
        tableView.reloadSections(IndexSet(integer: Section.attribution.rawValue), with: .automatic)

        Task { @MainActor in
            do {
                self.attribution = try await SpendOwl.attribution()
            } catch let err as SpendOwlError {
                self.error = err
            } catch {
                self.error = .unknown(error)
            }
            self.isLoading = false
            self.tableView.reloadSections(IndexSet(integer: Section.attribution.rawValue), with: .automatic)
        }
    }

    private func setUserId() {
        guard !userId.isEmpty else { return }
        SpendOwl.setUserId(userId)
        showAlert(title: "User ID Set", message: "User ID has been set to: \(userId)")
    }

    private func clearUserId() {
        SpendOwl.clearUserId()
        userId = ""
        tableView.reloadSections(IndexSet(integer: Section.userIdentity.rawValue), with: .automatic)
        showAlert(title: "User ID Cleared", message: "User ID has been cleared.")
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .attribution:
            if isLoading { return 1 }
            if let _ = attribution { return 8 } // 7 fields + button
            if let _ = error { return 2 } // error + button
            return 1 // just button
        case .userIdentity:
            return 3 // text field + set button + clear button
        case .purchases:
            return 1
        case .debug:
            return 2
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .attribution: return "Attribution"
        case .userIdentity: return "User Identity"
        case .purchases: return "Purchase Tracking"
        case .debug: return "Debug"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .attribution:
            return "Attribution data from Apple Ads via SpendOwl backend."
        case .userIdentity:
            return "Set a user ID to link attribution with your user accounts."
        case .purchases:
            return "StoreKit 2 purchases are tracked automatically for ROAS calculation. Works alongside RevenueCat or Adapty."
        case .debug:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .attribution:
            return attributionCell(for: indexPath)
        case .userIdentity:
            return userIdentityCell(for: indexPath)
        case .purchases:
            return purchasesCell(for: indexPath)
        case .debug:
            return debugCell(for: indexPath)
        }
    }

    // MARK: - Cell Builders

    private func attributionCell(for indexPath: IndexPath) -> UITableViewCell {
        if isLoading {
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var config = cell.defaultContentConfiguration()
            config.text = "Fetching attribution..."
            config.textProperties.color = .secondaryLabel
            cell.contentConfiguration = config
            cell.accessoryView = {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                return spinner
            }()
            return cell
        }

        if let attribution {
            let fields: [(String, String)] = [
                ("Status", attribution.status.displayName),
                ("Campaign", attribution.campaignName ?? "-"),
                ("Campaign ID", attribution.campaignId.map(String.init) ?? "-"),
                ("Ad Group", attribution.adGroupName ?? "-"),
                ("Keyword", attribution.keyword ?? "-"),
                ("Country", attribution.countryOrRegion ?? "-"),
                ("Conversion", attribution.conversionType ?? "-")
            ]

            if indexPath.row < fields.count {
                let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
                var config = cell.defaultContentConfiguration()
                config.text = fields[indexPath.row].0
                config.secondaryText = fields[indexPath.row].1
                config.secondaryTextProperties.color = .secondaryLabel
                cell.contentConfiguration = config
                cell.accessoryView = nil
                cell.selectionStyle = .none
                return cell
            }
        }

        if let error, indexPath.row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var config = cell.defaultContentConfiguration()
            config.text = "Error"
            config.secondaryText = error.localizedDescription
            config.secondaryTextProperties.color = .systemRed
            cell.contentConfiguration = config
            cell.accessoryView = nil
            cell.selectionStyle = .none
            return cell
        }

        // Button row
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = "Fetch Attribution"
        config.textProperties.color = .systemBlue
        cell.contentConfiguration = config
        cell.accessoryView = nil
        return cell
    }

    private func userIdentityCell(for indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.row {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "TextFieldCell", for: indexPath) as! TextFieldCell
            cell.configure(placeholder: "User ID", text: userId) { [weak self] text in
                self?.userId = text
            }
            return cell
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var config = cell.defaultContentConfiguration()
            config.text = "Set User ID"
            config.textProperties.color = .systemBlue
            cell.contentConfiguration = config
            return cell
        case 2:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var config = cell.defaultContentConfiguration()
            config.text = "Clear User ID"
            config.textProperties.color = .systemRed
            cell.contentConfiguration = config
            return cell
        default:
            return UITableViewCell()
        }
    }

    private func purchasesCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = "Status"
        config.secondaryText = "Automatic"
        config.secondaryTextProperties.color = .systemGreen
        config.image = UIImage(systemName: "checkmark.circle.fill")
        config.imageProperties.tintColor = .systemGreen
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        return cell
    }

    private func debugCell(for indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.row {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchCell
            cell.configure(title: "Enable Logging", isOn: SpendOwl.enableLogging) { isOn in
                SpendOwl.enableLogging = isOn
            }
            return cell
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var config = cell.defaultContentConfiguration()
            config.text = "Configured"
            config.secondaryText = SpendOwl.isConfigured ? "Yes" : "No"
            config.secondaryTextProperties.color = SpendOwl.isConfigured ? .systemGreen : .systemRed
            cell.contentConfiguration = config
            cell.selectionStyle = .none
            return cell
        default:
            return UITableViewCell()
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)! {
        case .attribution:
            let buttonRow = (attribution != nil) ? 7 : (error != nil) ? 1 : 0
            if indexPath.row == buttonRow {
                fetchAttribution()
            }
        case .userIdentity:
            if indexPath.row == 1 {
                setUserId()
            } else if indexPath.row == 2 {
                clearUserId()
            }
        case .purchases:
            break
        case .debug:
            break
        }
    }
}

// MARK: - AttributionStatus Extension

extension AttributionStatus {
    var displayName: String {
        switch self {
        case .attributed: return "Attributed"
        case .organic: return "Organic"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - TextFieldCell

class TextFieldCell: UITableViewCell {
    private let textField = UITextField()
    private var onTextChange: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupTextField()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTextField() {
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        contentView.addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            textField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        selectionStyle = .none
    }

    func configure(placeholder: String, text: String, onTextChange: @escaping (String) -> Void) {
        textField.placeholder = placeholder
        textField.text = text
        self.onTextChange = onTextChange
    }

    @objc private func textChanged() {
        onTextChange?(textField.text ?? "")
    }
}

// MARK: - SwitchCell

class SwitchCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let toggle = UISwitch()
    private var onToggle: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)

        contentView.addSubview(titleLabel)
        contentView.addSubview(toggle)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        selectionStyle = .none
    }

    func configure(title: String, isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        titleLabel.text = title
        toggle.isOn = isOn
        self.onToggle = onToggle
    }

    @objc private func toggleChanged() {
        onToggle?(toggle.isOn)
    }
}

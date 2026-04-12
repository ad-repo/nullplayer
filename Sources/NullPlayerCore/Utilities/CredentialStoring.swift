import Foundation

public protocol CredentialStoring: AnyObject {
    func setString(_ value: String, forKey key: String) -> Bool
    func getString(forKey key: String) -> String?
    func setData(_ data: Data, forKey key: String) -> Bool
    func getData(forKey key: String) -> Data?
    func delete(forKey key: String)
}

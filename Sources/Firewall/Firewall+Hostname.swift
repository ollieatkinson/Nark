import Darwin
import Foundation

extension Firewall {

    public enum Hostname {

        /// Rules accept DNS names or literal IPs, never URLs, ports, or wildcard expressions.
        public static func normalize(_ input: String) -> String? {
            var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if value.hasSuffix(".") {
                value.removeLast()
            }
            guard !value.isEmpty, value.utf8.count <= 253 else {
                return nil
            }
            var v4 = in_addr()
            var v6 = in6_addr()
            if inet_pton(AF_INET, value, &v4) == 1 {
                return value
            }
            if inet_pton(AF_INET6, value, &v6) == 1 {
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                guard inet_ntop(AF_INET6, &v6, &buffer, socklen_t(buffer.count)) != nil else {
                    return nil
                }
                return String(
                    decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self
                )
            }
            let labels = value.split(separator: ".", omittingEmptySubsequences: false)
            guard
                labels.allSatisfy({ label in
                    !label.isEmpty && label.utf8.count <= 63 && label.first != "-"
                        && label.last != "-"
                        && label.utf8.allSatisfy {
                            (97 ... 122).contains($0) || (48 ... 57)
                                .contains($0) || $0 == 45 || $0 == 95
                        }
                })
            else {
                return nil
            }
            return value
        }

        public static func matches(_ host: String, domain: String) -> Bool {
            guard let host = normalize(host), let domain = normalize(domain) else {
                return false
            }
            var v4 = in_addr()
            if domain.contains(":") || inet_pton(AF_INET, domain, &v4) == 1 {
                return host == domain
            }
            return host == domain || host.hasSuffix("." + domain)
        }
    }
}

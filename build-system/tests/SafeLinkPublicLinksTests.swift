import Foundation

@main
struct SafeLinkPublicLinksTests {
    static func main() {
        precondition(safeLinkPublicLink("kkkkk", prefix: nil) == "https://safelink.chat/kkkkk")
        precondition(safeLinkPublicLink("+8618052866760", prefix: nil) == "https://safelink.chat/+8618052866760")
        precondition(safeLinkPublicLink("/group/42", prefix: "https://chat.example.com/") == "https://chat.example.com/group/42")
        precondition(safeLinkPublicLink("//kkkkk", prefix: "https://chat.example.com///") == "https://chat.example.com/kkkkk")
        precondition(safeLinkPublicLink("kkkkk", prefix: " https://chat.example.com/links/ \n") == "https://chat.example.com/links/kkkkk")
        precondition(safeLinkPublicLink("+8618052866760", prefix: "http://212.189.31.87:8080") == "http://212.189.31.87:8080/+8618052866760")
        precondition(safeLinkPublicLink("m/slug?x=1#test", prefix: "HTTPS://chat.example.com/") == "https://chat.example.com/m/slug?x=1#test")
        for prefix in ["", "chat.example.com", "javascript:alert(1)", "safelink://chat.example.com", "https://user:pass@chat.example.com", "https://chat.example.com/?x=1", "https://chat.example.com/#x", "https://t.me/", "https://www.telegram.me/", "https://TELEGRAM.DOG/", "https://chat.example.com:0/", "https://chat.example.com:65536/"] {
            precondition(safeLinkPublicLinkPrefix(prefix) == "https://safelink.chat/", prefix)
        }
        let footer = "Links [t.me/kkkkk](username), [safelink.chat/+8618052866760](phone)."
        let rewritten = safeLinkPublicLinkFooter(footer, prefix: "https://chat.example.com/")
        precondition(rewritten == "Links [chat.example.com/kkkkk](username), [chat.example.com/+8618052866760](phone).")
        precondition(safeLinkPublicLinkFooter("[t.me/kkkkk](username)", prefix: nil) == "[safelink.chat/kkkkk](username)")
        precondition(safeLinkPublicLinkFooter("[t.me/kkkkk](username)", prefix: "https://chat.example.com/$links/") == "[chat.example.com/$links/kkkkk](username)")
        precondition(safeLinkPublicLinkDisplay(safeLinkPublicLink("kkkkk", prefix: nil)) == "safelink.chat/kkkkk")
        print("SafeLink public link generation, displayed labels and copied URLs passed")
    }
}

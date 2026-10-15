import Foundation
import Testing

@main struct Runner {
    static func main() async {
        let code = await Testing.__swiftPMEntryPoint() as Int32
        exit(code)
    }
}

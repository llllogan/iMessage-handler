import Foundation
import Testing
@testable import iMessageHandler

struct AttributedBodyDecoderTests {
    @Test func typedStreamStringMarkerPreservesMessageWhitespace() throws {
        let attributedBody = try #require(Data(hex: """
        040B73747265616D747970656481E803840140848484124E5341747472696275746564537472696E67008484084E534F626A656374008592848484084E53537472696E67019484012B0F6974E2809973206C6F636B736564208684026949010D928484840C4E5344696374696F6E617279009484016901928496961D5F5F6B494D4D657373616765506172744174747269627574654E616D658692848484084E534E756D626572008484074E5356616C7565009484012A84999900868686
        """))

        let decoded = AttributedBodyDecoder().decode(text: nil, attributedBody: attributedBody)

        #expect(decoded.text == "it’s locksed ")
        #expect(decoded.source == "attributedBody")
    }
}

private extension Data {
    init?(hex: String) {
        let bytes = hex.filter { !$0.isWhitespace }
        guard bytes.count.isMultiple(of: 2) else {
            return nil
        }

        var data = Data()
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let next = bytes.index(index, offsetBy: 2)
            guard let byte = UInt8(bytes[index..<next], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = next
        }
        self = data
    }
}

import SwiftUI

/// The notices the libraries KaChat Chess ships ask to travel with it: the Apache and MIT
/// ones ask for attribution. Plain scrolling text, one card per library.
struct OpenSourceLicensesView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Notice: Identifiable {
        let id: String
        let name: String
        let license: String
        let holder: String
        let text: String
    }

    private static let apache2 = """
Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
"""

    private static let mit = """
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"""

    private static let notices: [Notice] = [
        Notice(id: "grpc-swift", name: "grpc-swift", license: "Apache License 2.0", holder: "Copyright 2015-2024, gRPC Authors", text: apache2),
        Notice(id: "swift-protobuf", name: "SwiftProtobuf", license: "Apache License 2.0", holder: "Copyright 2014-2024 Apple Inc. and the SwiftProtobuf project authors", text: apache2),
        Notice(id: "swift-nio", name: "SwiftNIO, swift-crypto, swift-log and the Swift Server ecosystem packages", license: "Apache License 2.0", holder: "Copyright 2017-2024 Apple Inc. and the SwiftNIO project authors", text: apache2),
        Notice(id: "secp256k1", name: "swift-secp256k1 (P256K)", license: "MIT", holder: "Copyright (c) 2021 21.dev and the swift-secp256k1 authors", text: mit),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("KaChat Chess is built with these open source libraries. Their authors ask that these notices travel with the app.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    ForEach(Self.notices) { notice in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(notice.name).font(.headline)
                                Spacer()
                                Text(notice.license)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            Text(notice.holder)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(notice.text)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.regularMaterial)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                        )
                    }
                }
                .padding(16)
            }
            .navigationTitle("Open Source Licenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

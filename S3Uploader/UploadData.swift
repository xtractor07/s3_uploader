//
//  UploadData.swift
//  S3Uploader
//
//  Created by Kumar Aman on 05/12/23.
//

import Foundation

struct CreateMultipartUploadResponse: Codable {
    let uploadId: String
    let fileKey: String

    enum CodingKeys: String, CodingKey {
        case uploadId = "UploadId"
        case fileKey = "fileKey"
    }
}

struct PreSignedURLResponse: Codable {
    struct Part: Codable {
        let signedUrl: String
        let partNumber: Int

        enum CodingKeys: String, CodingKey {
            case signedUrl = "signedUrl"
            case partNumber = "PartNumber"
        }
    }

    let parts: [Part]
}

//
//  UploadManager.swift
//  S3Uploader
//
//  Created by Kumar Aman on 04/12/23.
//

import Foundation

protocol UploadManagerDelegate {
    func uploadIdSuccess()
    func presignedSuccess()
    func uploadComplete()
}

struct UploadManager {
    //CHANINED
    //API CALL FOR UPLOAD-ID
    //API CALL FOR PARTS AND PRESIGNED-URL
    
    private func createMultipartUpload(name: String, mimeType: String, completion: @escaping (Result<CreateMultipartUploadResponse, Error>) -> Void) {
        let url = URL(string: "http://13.57.38.104:8080/uploads/createMultipartUpload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let uploadData: [String: Any] = [
            "name": name,
            "mimeType": mimeType
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: uploadData, options: [])
            request.httpBody = jsonData

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(URLError(.badServerResponse)))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(CreateMultipartUploadResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            }

            task.resume()
        } catch {
            completion(.failure(error))
        }
    }

    
    private func getMultipartPreSignedUrls(fileKey: String, uploadId: String, parts: Int, completion: @escaping (Result<PreSignedURLResponse, Error>) -> Void) {
        let url = URL(string: "http://13.57.38.104:8080/uploads/getMultipartPreSignedUrls")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let uploadData: [String: Any] = [
            "fileKey": fileKey,
            "UploadId": uploadId,
            "parts": parts
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: uploadData, options: [])
            request.httpBody = jsonData

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(URLError(.badServerResponse)))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(PreSignedURLResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            }

            task.resume()
        } catch {
            completion(.failure(error))
        }
    }

    func uploadMedia(to preSignedUrl: URL, fileURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: preSignedUrl)
        request.httpMethod = "PUT"
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        print("Upload Started!")
        do {
            let fileData = try Data(contentsOf: fileURL)
            let task = URLSession.shared.uploadTask(with: request, from: fileData) { _, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, 200...299 ~= httpResponse.statusCode else {
                    completion(.failure(URLError(.badServerResponse)))
                    return
                }
                completion(.success(()))
            }
            task.resume()
        } catch {
            completion(.failure(error))
        }
    }


    func initiateUploadSequence(_ fileName: String, _ fileUrl: URL, _ mimeType: String, _ parts: Int = 1, completion: @escaping (Result<Void, Error>) -> Void) {
        createMultipartUpload(name: fileName, mimeType: mimeType) { response in
            switch response {
            case .success(let success):
                print("Success")
                getMultipartPreSignedUrls(fileKey: success.fileKey, uploadId: success.uploadId, parts: parts) { result in
                    switch result {
                    case .success(let response):
                        print("Success (UploadUrl): \(response.parts[0].signedUrl)")
                        let preSigned = URL(string: response.parts[0].signedUrl)
                        uploadMedia(to: preSigned!, fileURL: fileUrl) { result in
                            switch result {
                            case .success(_):
                                print("UploadSuccess!")
                                completion(.success(()))
                            case .failure(let error):
                                print("Error: \(error)")
                                completion(.failure(error))
                            }
                        }
                        
                    case .failure(let error):
                        print("Error: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
            
            case .failure(let error):
                print("Error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

}

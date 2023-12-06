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

struct UploadTask {
    let fileName: String
    let fileURL: URL
    let mimeType: String
    let parts: Int
    let completion: (Result<Void, Error>) -> Void
}

struct CompleteUploadRequest: Encodable {
    let fileKey: String
    let UploadId: String
    let parts: [Part]
}

struct Part: Encodable {
    let PartNumber: Int
    let ETag: String
}

class UploadManager {
    //CHANINED
    //API CALL FOR UPLOAD-ID
    //API CALL FOR PARTS AND PRESIGNED-URL
    
    private var uploadQueue: [UploadTask] = []
    private var isUploading = false
    
    private func performNetworkRequest(url: URL, httpMethod: String, body: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            completion(.success(data))
        }
        task.resume()
    }

    
    private func createMultipartUpload(name: String, mimeType: String, completion: @escaping (Result<CreateMultipartUploadResponse, Error>) -> Void) {
        let url = URL(string: "http://13.57.38.104:8080/uploads/createMultipartUpload")!
        let uploadData = ["name": name, "mimeType": mimeType]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: uploadData, options: [])
            performNetworkRequest(url: url, httpMethod: "POST", body: jsonData) { result in
                switch result {
                case .success(let data):
                    do {
                        let response = try JSONDecoder().decode(CreateMultipartUploadResponse.self, from: data)
                        completion(.success(response))
                    } catch {
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
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

    func uploadMedia(to preSignedUrl: URL, fileURL: URL, mimeType: String, completion: @escaping (Result<String?, Error>) -> Void) {
        var request = URLRequest(url: preSignedUrl)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
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

                // Extracting ETag from the response headers
                let etag = httpResponse.allHeaderFields["Etag"] as? String
                // Passing ETag in the success completion
                completion(.success(etag))
            }
            task.resume()
        } catch {
            completion(.failure(error))
        }
    }

    
    func completeMultipartUpload(fileKey: String, uploadId: String, parts: [Part], completion: @escaping (Result<Void, Error>) -> Void) {
        let url = URL(string: "http://13.57.38.104:8080/uploads/completeMultipartUpload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let uploadData = CompleteUploadRequest(fileKey: fileKey, UploadId: uploadId, parts: parts)

        do {
            let jsonData = try JSONEncoder().encode(uploadData)
            request.httpBody = jsonData

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
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
        let task = UploadTask(fileName: fileName, fileURL: fileUrl, mimeType: mimeType, parts: parts, completion: completion)
        uploadQueue.append(task)
        executeNextUpload()
    }
    
    private func executeNextUpload() {
        guard !isUploading, let nextTask = uploadQueue.first else { return }

        isUploading = true
        performUploadTask(task: nextTask)
    }
    
    private func performUploadTask(task: UploadTask) {
        // Step 1: Create multipart upload
        createMultipartUpload(name: task.fileName, mimeType: task.mimeType) { [weak self] result in
            switch result {
            case .success(let uploadResponse):
                // Step 2: Get presigned URLs with the obtained uploadId
                self?.getMultipartPreSignedUrls(fileKey: uploadResponse.fileKey, uploadId: uploadResponse.uploadId, parts: task.parts) { presignedResult in
                    switch presignedResult {
                    case .success(let presignedResponse):
                        // Assuming you're dealing with a single part for simplicity
                        guard let preSignedUrlString = presignedResponse.parts.first?.signedUrl,
                              let preSignedUrl = URL(string: preSignedUrlString) else {
                            return
                        }
                        // Step 3: Perform the actual media upload
                        self?.uploadMedia(to: preSignedUrl, fileURL: task.fileURL, mimeType: task.mimeType) { uploadResult in
                            switch(uploadResult) {
                            case .success(let etag):
                                if let unwrappedEtag = etag {
                                    print("Etag: \(unwrappedEtag)")
                                    let parts = [Part(PartNumber: task.parts, ETag: unwrappedEtag.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))]
                                    print("Part: \(parts)")
                                    self?.completeMultipartUpload(fileKey: task.fileName, uploadId: uploadResponse.uploadId, parts: parts) { result in
                                        switch result {
                                        case .success(_):
                                            print("Multipart Complete!")
                                        case .failure(_):
                                            print("Multipart Failed!")
                                        }
                                    }
                                    print("Upload Success!")
                                }
                                
                            case .failure(_):
                                print("Upload Failed!")
                            }
                            let voidResult: Result<Void, Error> = uploadResult.map { _ in () }
                            self?.completeUploadTask(task: task, result: voidResult)
//                            self?.completeUploadTask(task: task, result: uploadResult)
                        }
                    case .failure(let error):
                        self?.completeUploadTask(task: task, result: .failure(error))
                    }
                }
            case .failure(let error):
//                self?.completeUploadTask(task: task, result: .failure(error))
                print("Error: \(error.localizedDescription)")
            }
        }
    }

    private func completeUploadTask(task: UploadTask, result: Result<Void, Error>) {
        // Removing the temporary file
        removeTemporaryFile(fileURL: task.fileURL)

        // Notifying completion (success or failure)
        task.completion(result)

        // Update the queue and the uploading flag
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Remove the completed task from the queue
            self.uploadQueue.removeFirst()

            // Mark current upload as completed
            self.isUploading = false

            // Trigger the next upload
            self.executeNextUpload()
        }
    }
    
    private func removeTemporaryFile(fileURL: URL) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
                print("Temporary file removed: \(fileURL)")
            } catch {
                print("Failed to remove temporary file: \(error)")
            }
        } else {
            print("File does not exist, no need to delete: \(fileURL)")
        }
    }
}

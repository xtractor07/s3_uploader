//
//  ViewController.swift
//  S3Uploader
//
//  Created by Kumar Aman on 04/12/23.
//

import UIKit
import PhotosUI
import UniformTypeIdentifiers
class ViewController: UIViewController, PHPickerViewControllerDelegate {

    var uploadManager = UploadManager()
    @IBOutlet weak var createUploadIdBtn: UIButton!
    @IBOutlet weak var uploadSuccessBtn: UIButton!
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    @IBAction func createMultipartApiPressed(_ sender: UIButton) {
        presentImageAndVideoPicker()
    }
    
    func presentImageAndVideoPicker() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0  // 0 for unlimited selection
        config.filter = .any(of: [.images, .videos])
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    // Delegate method
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        for result in results {
            if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                // Handle image
                result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                    guard let self = self, let image = object as? UIImage, error == nil else {
                        print("Error loading image: \(error?.localizedDescription ?? "Unknown error")")
                        return
                    }
                    self.handleImage(image)
                }
            } else if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                // Handle video
                result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] data, error in
                    guard let self = self, let data = data, error == nil else {
                        print("Error loading video data: \(error?.localizedDescription ?? "Unknown error")")
                        return
                    }
                    self.handleMediaData(data, originalFileName: "video.mp4", isVideo: true)
                }
            }
        }
    }



    private func handleImage(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 1.0) else {
            print("Could not convert image to JPEG data")
            return
        }
        handleMediaData(imageData, originalFileName: "image.jpg", isVideo: false)
    }

    private func handleMediaData(_ data: Data, originalFileName: String, isVideo: Bool) {
        let fileExtension = isVideo ? "mp4" : "jpg"
        let uniqueFileName = "\(UUID().uuidString).\(fileExtension)"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueFileName)

        do {
            try data.write(to: tempURL)
            let mimeType = getMimeType(for: tempURL)
        
            self.uploadManager.initiateUploadSequence(uniqueFileName, tempURL, mimeType) { result in
                switch result {
                case .success(_):
                    DispatchQueue.main.async { [self] in
                        uploadSuccessBtn.backgroundColor = UIColor.systemGreen
                    }
                case .failure(let error):
                    print("Error: \(error.localizedDescription)")
                    DispatchQueue.main.async { [self] in
                        uploadSuccessBtn.backgroundColor = UIColor.systemRed
                    }
                }
            }
        } catch {
            print("Error saving media data: \(error)")
        }
    }
    
    func getMimeType(for url: URL) -> String {
        guard let utType = UTType(filenameExtension: url.pathExtension) else {
            return "application/octet-stream" // default or unknown MIME type
        }
        return utType.preferredMIMEType ?? "application/octet-stream"
    }
    
    func copyVideoToAppTemporaryDirectory(originalURL: URL, completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let fileManager = FileManager.default
            let tempDirectory = fileManager.temporaryDirectory
            let localURL = tempDirectory.appendingPathComponent(originalURL.lastPathComponent)

            do {
                if fileManager.fileExists(atPath: localURL.path) {
                    try fileManager.removeItem(at: localURL)
                }
                try fileManager.copyItem(at: originalURL, to: localURL)
                DispatchQueue.main.async {
                    completion(localURL)
                }
            } catch {
                print("Error copying file: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}


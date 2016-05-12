//
//  Sequence.swift
//  Camera_IMU
//
// Copyright Simon Lucey 2015, All rights Reserved......

import Foundation
import UIKit

struct Sequence
{
    var name:String = ""
    
    init(name:String)
    {
        self.name = name
    }
}

@objc class Sequences : NSObject
{
    var sequences:[Sequence] = []
    var fileMgr: NSFileManager = NSFileManager.defaultManager()
    var appDir: NSURL = NSURL()
    
    var activeSequence: Int = -1
    var currentStep: Int = -1
    
    override init(){
        super.init()
        // Document directory access: http://stackoverflow.com/a/27722526
        self.appDir = self.fileMgr.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)[0] as! NSURL
        
        let f = indexFile()
        if (!self.fileMgr.fileExistsAtPath(f)) {
            // Start a new index
            writeJsonIndex()
        } else {
            // Read in the existing index
            readJsonIndex()
        }
        debug()
        
        if let directoryContents =
            self.fileMgr.contentsOfDirectoryAtPath(self.appDir.path!, error: nil) {
                println(directoryContents)
        }
    }
    
    func indexFile() -> String {
        return self.appDir.path!.stringByAppendingPathComponent("index.json")
    }
    
    func debug() {
        println("Sequences:")
        for seq in sequences {
            println("\t\(seq.name)")
        }
    }
    
    func writeJsonIndex() {
        var names: [String] = []
        for seq in sequences {
            names.append(seq.name)
        }
        println("Writing JSON. Names: \(names)")
        var json = ["sequences": names, "active": activeSequence, "currentStep": currentStep ]
        if let data = NSJSONSerialization.dataWithJSONObject(json, options: .PrettyPrinted, error: nil) {
            self.fileMgr.createFileAtPath(indexFile(), contents:data, attributes:nil)
        }
    }
    
    func readJsonIndex() {
        var missingDir = false
        if let data = self.fileMgr.contentsAtPath(indexFile()) {
            if let json = NSJSONSerialization.JSONObjectWithData(data, options: .MutableContainers, error: nil) as! NSDictionary? {
                sequences.removeAll(keepCapacity: true)
                for name in (json["sequences"] as! [String]) {
                    let dir = getDirFor(name)
                    if self.fileMgr.fileExistsAtPath(dir) {
                        sequences.append(Sequence(name: name))
                    } else {
                        missingDir = true
                    }
                }
                if let activeVal: AnyObject = json["active"] {
                    activeSequence = activeVal as! Int
                    if let currentVal: AnyObject = json["currentStep"] {
                        currentStep = currentVal as! Int
                    } else {
                        currentStep = 0
                    }
                } else {
                    activeSequence = -1
                    currentStep = -1
                }
            }
        }
        
        if missingDir {
            // Sequence directories have been removed. Update the index
            writeJsonIndex()
        }
    }
    
    func beginRecording(name: String) -> Bool {
        for (index, seq) in enumerate(self.sequences) {
            if seq.name == name {
                println("Sequence with name \(name) already exists!")
                return false
            }
        }
        
        let newDir = self.appDir.path!.stringByAppendingPathComponent(name)
        self.fileMgr.createDirectoryAtPath(newDir, withIntermediateDirectories: true, attributes: nil, error: nil)
        sequences.append(Sequence(name: name))
        
        activeSequence = sequences.count - 1
        currentStep = 0
        writeJsonIndex()
        
        return true
    }
    
    func changeActiveSequence(index: Int) -> Bool {
        if index < 0 || index >= sequences.count {
            return false
        }
        activeSequence = index
        currentStep = 0
        writeJsonIndex()
        return true
    }
    
    func imageForSequence(index: Int) -> UIImage? {
        let imagePath = getDirFor(sequences[index].name).stringByAppendingPathComponent("thumbnail.jpg")
        if let data = NSData(contentsOfFile: imagePath) {
            return UIImage(data: data)
        }
        return nil;
    }
    
    func activeName() -> String {
        if activeSequence < 0 || activeSequence >= sequences.count {
            return ""
        }
        return sequences[activeSequence].name
    }
    
    func lastStep() {
        if currentStep > 0 {
            currentStep -= 1
            writeJsonIndex()
        }
    }
    func nextStep() {
        currentStep += 1
        writeJsonIndex()
    }
    
    func getActiveDir() -> String {
        if activeSequence < 0 { return "" }
        
        return getDirFor(sequences[activeSequence].name)
    }
    
    func getDirFor(name: String) -> String {
        return self.appDir.path!.stringByAppendingPathComponent(name)
    }

    func setScanForActiveSequence(url: NSURL!) {
        saveActiveFile(url, to: "scan.mp4")
    }
    
    func setPortraitForActiveSequence(url: NSURL!) {
        if activeSequence < 0 { return }
        
        let imagePath = getActiveDir().stringByAppendingPathComponent("portrait.jpg")
        let thumbPath = getActiveDir().stringByAppendingPathComponent("thumbnail.jpg")
        
        if let srcPath = url.path {
            let imageData: NSData? = self.fileMgr.contentsAtPath(srcPath)
            if imageData == nil {
                println("WARNING: Cannot read image from \(srcPath)")
                return
            }
            
            self.fileMgr.removeItemAtPath(srcPath, error: nil)
            
            let success = self.fileMgr.createFileAtPath(imagePath, contents:imageData, attributes:nil)
            if !success {
                println("WARNING: Unable to move portrait image \(srcPath) to \(imagePath)")
                return
            } else {
                println("Successfully moved portrait image \(srcPath) to \(imagePath)")
            }
            
            println("Attempting to make thumbnail...")
            if let image = UIImage(data: imageData!) {
                let ratio = image.size.height/image.size.width
                let size: CGSize = CGSize(width: 128, height: Int(128*ratio))
                UIGraphicsBeginImageContext(size)
                image.drawInRect(CGRectMake(0, 0, size.width, size.height))
                let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
                UIImageJPEGRepresentation(thumbnail, 0.98).writeToFile(thumbPath, atomically: true)
            } else {
                println("WARNING: Unable to create UIImage from data...")
            }
        }
    }
    
    func setScaleQRForActiveSequence(url: NSURL!) {
        saveActiveFile(url, to: "qr.jpg")
    }
    
    func setScaleVideoForActiveSequence(url: NSURL!) {
        saveActiveFile(url, to: "imu.mp4")
    }
    
    func setIMULogForActiveSequence(imuLogUrl: NSURL!) {
        saveActiveFile(imuLogUrl, to: "imu.txt")
    }
    
    func saveActiveFile(from: NSURL, to: String) {
        if activeSequence < 0 { return }
        
        let videoPath = getActiveDir().stringByAppendingPathComponent(to)
        
        if let srcPath = from.path {
            if !self.fileMgr.fileExistsAtPath(srcPath) {
                println("Source doesn't exist: \(srcPath)")
                return
            }
            
            // moveItemAtPath doesn't allow overwriting
            self.fileMgr.removeItemAtPath(videoPath, error: nil)
            let success = self.fileMgr.moveItemAtPath(srcPath, toPath: videoPath, error: nil)
            if !success {
                println("WARNING: Unable to move file \(srcPath) to \(videoPath)")
            } else {
                println("Successfully moved file \(srcPath) to \(videoPath)")
            }
        }
    }
    
    func add(name: String) {
        println("Adding sequence: \(name)...")
        for (index, seq) in enumerate(self.sequences) {
            if seq.name == name {
                println("Sequence with name \(name) already exists!")
                return
            }
        }
        let newDir = self.appDir.path!.stringByAppendingPathComponent(name)
        self.fileMgr.createDirectoryAtPath(newDir, withIntermediateDirectories: true, attributes: nil, error: nil)
        sequences.append(Sequence(name: name))
        debug()
        // Update the index file
        writeJsonIndex()
    }
    
    func remove(name: String) {
        println("Deleting \(name)")
        // Delete folder?
        let newDir = self.appDir.path!.stringByAppendingPathComponent(name)
        let success = self.fileMgr.removeItemAtPath(newDir, error: nil)
        println("Removing \(newDir). Success: \(success)")

        for (index, seq) in enumerate(self.sequences) {
            if seq.name == name {
                println("Found \(name). Deleting...")
                sequences.removeAtIndex(index)
                
                // Update the index file
                writeJsonIndex()
                return
            }
        }
    }
    
    func removeIndex(index: Int) {
        let name = sequences[index].name
        println("Deleting \(name)")
        // Delete folder?
        let newDir = self.appDir.path!.stringByAppendingPathComponent(name)
        let success = self.fileMgr.removeItemAtPath(newDir, error: nil)
        println("Removing \(newDir). Success: \(success)")

        sequences.removeAtIndex(index)
        
        // Update the index file
        writeJsonIndex()
    }
    
    func at(index: Int) -> Sequence {
        return sequences[index]
    }
    
    func count() -> Int {
        return sequences.count
    }
}
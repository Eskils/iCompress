//
//  File.swift
//  ImageCompressionEngine
//
//  Created by Eskil Sviggum on 02/04/2022.
//

import SwiftUI

struct ImageViewer: View {
    let contentView: ContentView
    @Binding var isRunning: Bool
    
    @State var originalImageSize: Int = 1
    @State var originalImage: UIImage?
    @State var compressedImage: UIImage?
    @State var progress: CGFloat?
    @State var shouldUpdateMergedImage = false
    
    @State var imageScaleTemp: CGSize = .zero
    @State var prevPos: CGSize = .zero
    @State var imageRect: CGRect = .zero
    
    @State var imageSize: String?
    @State var imageReduction: Int?
    
    @State var hasSetInitialSize: Bool = false
    
    
    @Environment(\.safeAreaInsets) var safeAreaInsets
    
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ZStack {
                    Image(uiImage: mergedImage(geo: geo, rect: imageRect, shouldUpdate: shouldUpdateMergedImage || isRunning))
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .gesture(
                            DragGesture().simultaneously(with: MagnificationGesture())
                                .onChanged(shouldTransformImage(gestureResult:))
                                .onEnded(commitTransformImage(gestureResult:))
                        )
                }
                .overlay {
                    if isRunning {
                        ProgressView()
                            .tint(.white)
                            .position(x: imageSplitWidth(geo: geo), y: imageRect.minY + geo.size.height / 2)
                    }
                }
                
                ZStack {
                    Rectangle()
                        .frame(width: 30)
                        .foregroundColor(Color.black)
                    Rectangle()
                        .frame(width: 3)
                        .foregroundColor(Color(UIColor.white))
                    Circle()
                        .frame(width: 30, height: 30)
                        .foregroundColor(Color(UIColor.white))
                        .overlay {
                            Image(systemName: "arrowtriangle.left.and.line.vertical.and.arrowtriangle.right")
                                .resizable()
                                .foregroundColor(Color(UIColor.white))
                                .frame(width: 20, height: 20)
                        }
                        
                }
                .edgesIgnoringSafeArea(.vertical)
                    .frame(width: 46, height: geo.size.height)
                    .position(x: min(geo.size.width, progress ?? geo.size.width/2), y: geo.size.height/2)
                    .blendMode(.exclusion)
                    .gesture(
                        DragGesture()
                            .onChanged(didChangeProgress(progress:))
                    )
                
                if let imageSize = imageSize,
                   let imageReduction = imageReduction {
                    HStack(spacing: 20) {
                        Label(imageSize, systemImage: "scalemass")
                        Label("\(imageReduction < 0 ? "+" : "-") \(abs(imageReduction)) %", systemImage: imageReduction < 0 ? "arrow.up.square" : "arrow.down.square")
                        Button(action: showTooltipImageSize) { 
                            Image(systemName: "questionmark.circle.fill")
                        }.overlay { 
                            GeometryReader { geo in
                                Color.clear
                                    .preference(key: PointPreference.self, value: geo.frame(in: .global).origin)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)
                    .shadow(color: Color(uiColor: UIColor.label).opacity(0.2), radius: 4, x: 0, y: 0)
                    .position(x: geo.size.width / 2, y: geo.size.height - 24 - safeAreaInsets.bottom)
                    .onPreferenceChange(PointPreference.self) { new in
                        self.contentView.imageSizeButtonPos = new
                    }
                }
                
            }.background(Color(UIColor.systemGray6))
        }
        .onAppear(perform: didAppear)
    }
    
    func imageScale() -> CGFloat {
        let originalSize = originalImage?.size.width ?? 400
        return imageRect.width / originalSize
    }
    
    func didAppear() {
        
        _ = contentView.compressionEngine.originalImage.listenToUpdates {
            originalImage = $0
            if !hasSetInitialSize {
                hasSetInitialSize = true
                imageRect.size = $0.size
                imageScaleTemp = $0.size
            } else {
                shouldUpdateMergedImage.toggle()
            }
            do {
                guard let imageData = originalImage?.jpegData(compressionQuality: 1) else { return }
                let compressedImageData = try contentView.compressionEngine.compress(data: imageData)
                originalImageSize = compressedImageData.count
            } catch {
                print(error)
            }
        }
        
        _ = contentView.compressionEngine.compressedImage.listenToUpdates {
            compressedImage = $0
            shouldUpdateMergedImage.toggle()
            updateImagestats()
        }
    }
    
    func imageSplitWidth(geo: GeometryProxy) -> CGFloat {
        let imgStart = imageRect.minX + geo.size.width / 2
        let prog = ((progress ?? geo.size.width/2))
        let wid = (imageRect.width / 2) - (prog - imgStart)
        return max(geo.size.width / 2, prog + (wid / 2))
    }
    
    func mergedImage(geo: GeometryProxy, rect: CGRect, shouldUpdate: Bool) -> UIImage {
        var left: UIImage!
        var right: UIImage!
        if let img = originalImage { left = img } else { left = UIImage() }
        if let img = compressedImage { right = img } else { right = left }
        
        let pos = CGPoint(x: imageRect.minX * imageScale() + (geo.size.width / 2), y: imageRect.minY * imageScale() + (geo.size.height / 2))
        
        let progress = progress ?? geo.size.width / 2
        let imgStart = rect.minX * imageScale() + geo.size.width / 2
        let wid = (imageRect.width / 2) - (progress - imgStart)
        let prog = 1 - (wid / rect.width)
        
        return createMergedImage(left: left, right: right, progress: min(1, max(0, prog)), size: left.size, isRunning: isRunning, renderSize: geo.size, imageFrame: CGRect(origin: pos, size: rect.size)) ?? UIImage()
    }
    
    func didChangeProgress(progress: DragGesture.Value) {
        self.progress = max(0, progress.location.x)
        shouldUpdateMergedImage.toggle()
    }
    
    func updateImagestats() {
        guard let export = contentView.compressionEngine.createWackImageData()
        else { return }
        let size = export.count
        
        let percentage = Int((Float(size) / Float(self.originalImageSize)) * 100)
        let magnitude = floor(log10(Float(size))/3)
        let kbSize = size / Int(pow(10, 3 * magnitude))
        imageSize = "\(kbSize) \(suffixFromSizeMagnitude(size))"
        imageReduction = 100 - percentage
    }
    
    func suffixFromSizeMagnitude(_ size: Int, allowedDigits: Int = 3) -> String {
        let magnitude = Int(log10(Float(size))/3)
        switch magnitude {
        case 0: return "bytes"
        case 1: return "kB"
        case 2: return "MB"
        case 3: return "GB"
        default: return ""
        }
    }
    
    func showTooltipImageSize() {
        withAnimation {
            self.contentView.shouldDisplayImageSizeTooltip.toggle()
        }
    }
    
    func shouldTransformImage(gestureResult: SimultaneousGesture<DragGesture, MagnificationGesture>.Value) {
        
        let drag = gestureResult.first
        let newScale = gestureResult.second ?? 1
        
        imageRect.size.width = imageScaleTemp.width * newScale
        imageRect.size.height = imageScaleTemp.height * newScale
        let scale = imageScale()
        
        let pos = drag?.translation ?? .zero
        imageRect.origin.x += (pos.width - prevPos.width) / scale
        imageRect.origin.y += (pos.height - prevPos.height) / scale
        prevPos = pos
        
        shouldUpdateMergedImage.toggle()
    }
    
    func commitTransformImage(gestureResult: SimultaneousGesture<DragGesture, MagnificationGesture>.Value) {
        
        imageScaleTemp = imageRect.size
        prevPos = .zero
        shouldUpdateMergedImage.toggle()
    }
}

//
//  File.swift
//  ImageCompressionEngine
//
//  Created by Eskil Sviggum on 02/04/2022.
//

import SwiftUI

struct ImageToolbar: View {
    let contentView: ContentView
    
    @Binding var segmentSize: Int
    @Binding var hasImage: Bool
    @State var threshold: Float = 0
    
    @State var subsampleSize: Int = 1
    
    @State var numColors: Int = 256
    
    @State var shouldUpdateRender: Bool = false
    
    @State var shouldDesampleColor: Bool = false
    @State var shouldUseDitheringVal: Bool = false
    @State var shouldUseGrayscaleVal: Bool = false
    @State var shouldUseDithering: Binding<Bool>!
    @State var shouldUseGrayscale: Binding<Bool> = .constant(false)
    
    @Binding var isRunning: Bool
    
    @State var originalImage: UIImage?
    
    @State var templateImageNames = ["sunset", "leaf", "beach", "mountain", "city"]
    
    var body: some View {
        GeometryReader { geo in
            ScrollView {
            VStack {
                VStack {
                    Text("Image Compression Engine")
                        .font(.title2)
                        .bold()
                        .frame(width: geo.size.width, alignment: .center)
                    
                    Button(action: presentImagePicker) {
                        Label("Choose image from library", systemImage: "photo.on.rectangle.angled")
                            .padding(8)
                            .foregroundColor(.white)
                            .background(Color.accentColor)
                            .cornerRadius(8)
                    }
                    Text("Or try a demo image: ")
                    HStack {
                        ForEach(templateImageNames, id: \.self) { (name) in
                            let image = UIImage(named: name)!
                            Button { 
                                contentView.imageName = name
                                contentView.didChooseImage(image: image)
                            } label: { 
                                Image(uiImage: image)
                                    .resizable()
                                    .cornerRadius(8)
                                    .frame(width: 52, height: 52)
                                    .overlay { 
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(lineWidth: 2)
                                    }
                            }
                        }
                    }
                }
                
                Divider()
                
                    VStack(spacing: 32) {
                        VStack {
                            HStack {
                                Text("Luma-channel")
                                    .bold()
                                Button(action: showTooltipLuma) { 
                                    Image(systemName: "questionmark.circle.fill")
                                }
                                .overlay { 
                                    GeometryReader { geo in
                                        Color.clear
                                            .preference(key: PointPreference.self, value: geo.frame(in: .global).origin)
                                    }
                                }
                            }                                
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onPreferenceChange(PointPreference.self) { new in
                                self.contentView.lumaButtonPos = new
                            }
                            VStack {
                                SliderView(title: "Segment size",
                                           unit: "px",
                                           min: 1,
                                           max: 50,
                                           initial: Float(segmentSize),
                                           handler: didUpdateSegmentSize(segmentSize:),
                                           valueTransform: segmentSizeValueTransform(_:))
                                
                                SliderView(title: "Threshold",
                                           unit: "%",
                                           unitScale: 100,
                                           handler: didUpdateThreshold(threshold:))
                                Toggle("Store image as grayscale", isOn: shouldUseGrayscale)
                            }.padding(.leading, 16)
                        }
                        
                        if !shouldUseGrayscaleVal {
                            
                            VStack {
                                HStack {
                                    Text("Chroma subsampling")
                                        .bold()
                                    Button(action: showTooltipChroma) { 
                                        Image(systemName: "questionmark.circle.fill")
                                    }.overlay { 
                                        GeometryReader { geo in
                                            Color.clear
                                                .preference(key: PointPreference.self, value: geo.frame(in: .global).origin)
                                        }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                    .onPreferenceChange(PointPreference.self) { new in
                                        self.contentView.chromaButtonPos = new
                                    }
                                VStack {
                                    SliderView(title: "Segment size",
                                               unit: "px",
                                               min: 1,
                                               max: Float(originalImage?.size.width ?? 100),
                                               initial: 1,
                                               handler: didUpdateSubsampleSize(segmentSize:),
                                               valueTransform: segmentSizeValueTransform(_:))
                                }.padding(.leading, 16)
                            }.transition(.move(edge: .top).combined(with: .opacity))
                            
                            VStack {
                                Toggle(isOn: Binding<Bool>(get: {
                                    return shouldDesampleColor
                                }, set: { new in
                                    withAnimation {
                                        shouldDesampleColor = new
                                        rerenderImage()
                                    }
                                })) {
                                    HStack {
                                        Text("Quantization")
                                            .bold()
                                        //.frame(maxWidth: .infinity, alignment: .leading)
                                        Button(action: showTooltipQuantization) { 
                                            Image(systemName: "questionmark.circle.fill")
                                        }.overlay { 
                                            GeometryReader { geo in
                                                Color.clear
                                                    .preference(key: PointPreference.self, value: geo.frame(in: .global).origin)
                                            }
                                        }
                                    }
                                    .onPreferenceChange(PointPreference.self) { new in
                                        self.contentView.quantizationButtonPos = new
                                    }
                                }
                                if (shouldDesampleColor) {
                                    VStack {
                                        Toggle("Should use dithering", isOn: shouldUseDithering)
                                        SliderView(title: "Num. colors", unit: "", min: 2, max: 256, initial: 256, handler: didUpdateDesampling(numColors:))
                                    }.padding(.leading, 16)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }.transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .disabled(!hasImage)
            }
            .frame(width: geo.size.width - 32)
            .padding(16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        }.onAppear(perform: didAppear)
    }
    
    func didAppear() {
        _ = contentView.compressionEngine.originalImage.listenToUpdates { 
            originalImage = $0
            rerenderImage(shouldRemakeDCT: true)
            hasImage = true
        }
        
        shouldUseDithering = binding(_shouldUseDitheringVal, withChangeHandler: didChangeDesamplingSwitch, transformHandler: nil, initialValue: false)
        shouldUseGrayscale = binding(_shouldUseGrayscaleVal, withChangeHandler: didChangeDesamplingSwitch, transformHandler: nil, initialValue: false, shouldAnimate: true)
    }
    
    func showTooltipLuma() {
        withAnimation { 
            contentView.shouldDisplayChromaTooltip = false
            contentView.shouldDisplayQuantizationTooltip = false
            contentView.shouldDisplayLumaTooltip.toggle()
        }
    }
    
    func showTooltipChroma() {
        withAnimation {
            contentView.shouldDisplayLumaTooltip = false
            contentView.shouldDisplayQuantizationTooltip = false
            contentView.shouldDisplayChromaTooltip.toggle()
        }
    }
    
    func showTooltipQuantization() {
        withAnimation {
            contentView.shouldDisplayChromaTooltip = false
            contentView.shouldDisplayLumaTooltip = false
            contentView.shouldDisplayQuantizationTooltip.toggle()
        }
    }
    
    func segmentSizeValueTransform(_ t: Float) -> Float {
        let size = Float(originalImage?.size.width ?? 100)
        return size / floor(size/t)
    }
    
    func didUpdateSegmentSize(segmentSize: Float) {
        self.segmentSize = Int(segmentSize)
        rerenderImage(shouldRemakeDCT: true)
    }
    
    func didUpdateThreshold(threshold: Float) {
        self.threshold = threshold  // TODO: Allow for passing a binding to SliderView
        rerenderImage()
    }
    
    func didUpdateSubsampleSize(segmentSize: Float) {
        self.subsampleSize = Int(segmentSize)
        rerenderImage()
    }
    
    func didUpdateDesampling(numColors: Float) {
        self.numColors = Int(numColors)
        rerenderImage()
    }
    
    func didChangeDesamplingSwitch(_ val: Bool) {
        rerenderImage()
    }
    
    func presentImagePicker() {
        //NOTE: If image picker is cancelled, imageName has been changed unfavorably
        contentView.imageName = "compressedImage"
        contentView.showsImagePicker = true
    }
    
    func rerenderImage(shouldRemakeDCT: Bool=false) {
        if isRunning { shouldUpdateRender = true; return }
        isRunning = true
        
        let compressionEngine = self.contentView.compressionEngine
        if compressionEngine.descriptions.luma == nil { isRunning = false; return }
        
        DispatchQueue.global().async {
            let shouldGenerateDCT = shouldRemakeDCT || compressionEngine.descriptions.frequencyDomain == nil
            compressionEngine.performFullCompression(
                thresold: self.threshold,
                segmentSize: self.segmentSize,
                subsampleSize: self.subsampleSize,
                numColors: self.numColors,
                shouldDither: self.shouldUseDitheringVal,
                shouldMakeGrayscalePallet: self.shouldUseGrayscaleVal,
                generateDCT: shouldGenerateDCT,
                shouldQuantize: self.shouldDesampleColor
            )
            
            isRunning = false
            if shouldUpdateRender {
                shouldUpdateRender = false
                rerenderImage()
            }
        }
    }
    
    
}

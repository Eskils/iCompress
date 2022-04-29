import SwiftUI

struct ContentView: View {
    
    var compressionEngine = CompressionEngine()
    
    @State var segmentSize: Int = 8
    @State var unalteredOriginalImage: UIImage?
    @State var showsImagePicker: Bool = false
    var imageSelection: Binding<UIImage?>!
    @State var isRunning: Bool = false
    @State var hasImage: Bool = false
    @State var shouldDisplayImport: Bool = false
    @State var imageName: String = "compressedImage"
    
    @State var shouldDisplayLumaTooltip: Bool = false
    @State var shouldDisplayChromaTooltip: Bool = false
    @State var shouldDisplayQuantizationTooltip: Bool = false
    @State var shouldDisplayImageSizeTooltip: Bool = false
    
    @State var lumaButtonPos: CGPoint?
    @State var chromaButtonPos: CGPoint?
    @State var quantizationButtonPos: CGPoint?
    @State var imageSizeButtonPos: CGPoint?
    @State var bottomBarFrame: CGRect?
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass: UserInterfaceSizeClass?
    
    init() {
        imageSelection = binding(_unalteredOriginalImage, withChangeHandler: didChooseImage(image:), initialValue: nil)
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if horizontalSizeClass == .regular {
                    HStack(spacing: 8) {
                        imageToolbar(geo: geo)
                            .frame(width: toolbarWidth(geo: geo))
                        imageViewer(geo: geo)
                            .frame(width: viewerWidth(geo: geo))
                            .edgesIgnoringSafeArea(.vertical)
                    }
                } else {
                    VStack(spacing: 8) {
                        imageViewer(geo: geo)
                            .frame(width: geo.size.width, height: geo.size.width)
                        imageToolbar(geo: geo)
                            .frame(width: geo.size.width)
                    }
                }
                
                if (shouldDisplayLumaTooltip) { 
                    TooltipView(text: TooltipText.luma, edge: (horizontalSizeClass == .regular) ? .top : .bottom, arrowXPos: lumaButtonPos?.x, shouldDisplay: $shouldDisplayLumaTooltip)
                    .position(y: lumaButtonPos?.y ?? 0)
                }
                if (shouldDisplayChromaTooltip) { 
                    TooltipView(text: TooltipText.chroma, edge: .bottom, arrowXPos: chromaButtonPos?.x, shouldDisplay: $shouldDisplayChromaTooltip)
                    .position(y: chromaButtonPos?.y ?? 0)
                }
                if (shouldDisplayQuantizationTooltip) { 
                    TooltipView(text: TooltipText.quantization, edge: .bottom, arrowXPos: quantizationButtonPos?.x, shouldDisplay: $shouldDisplayQuantizationTooltip)
                    .position(y: quantizationButtonPos?.y ?? 0)
                }
                if (shouldDisplayImageSizeTooltip) { 
                    TooltipView(text: TooltipText.imageSize, edge: (horizontalSizeClass == .regular) ? .bottom : .top, arrowXPos: imageSizeButtonPos?.x, shouldDisplay: $shouldDisplayImageSizeTooltip, shouldFollowXPos: (horizontalSizeClass == .regular))
                        .position(y: imageSizeButtonPos?.y ?? 0)
                }
            }
        }
        .sheet(isPresented: $showsImagePicker) { ImagePicker(image: imageSelection) }
        .fileImporter(isPresented: $shouldDisplayImport, allowedContentTypes: [.data], onCompletion: didChooseImport(_:))
    }
    
    func imageToolbar(geo: GeometryProxy) -> some View {
        VStack {
            ImageToolbar(contentView: self, segmentSize: $segmentSize, hasImage: $hasImage, isRunning: $isRunning)
                .background(Color(UIColor.systemBackground))
            HStack {
                /*Button(action: didPressImport) { 
                    Label("Import", systemImage: "square.and.arrow.down")
                        .padding(8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }*/
                
                Button(action: didPressExport) { 
                    Label("Export & reimport", systemImage: "square.and.arrow.up")
                        .padding(8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .disabled(!hasImage)
                }
                
                Button(action: didPressExportPNG) { 
                    Label("Export PNG", systemImage: "square.and.arrow.up")
                        .padding(8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .disabled(!hasImage)
                }
            }
            .padding(12)
            .frame(width: geo.size.width)
            .background(Color(uiColor: UIColor.systemGray5))
            .overlay {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: FramePreference.self, value: geo.frame(in: .global))
                }
            }
        }
        .onPreferenceChange(FramePreference.self) { new in
            self.bottomBarFrame = new
        }
    }
    
    func imageViewer(geo: GeometryProxy) -> some View {
            ImageViewer(contentView: self, isRunning: $isRunning)
                .background(Color(UIColor.secondarySystemBackground))
                .clipped()
    }
    
    func toolbarWidth(geo: GeometryProxy) -> CGFloat { return max(400, geo.size.width * 0.2) }
    func viewerWidth(geo: GeometryProxy) -> CGFloat { return geo.size.width - toolbarWidth(geo: geo) }
    
    func didChooseImage(image: UIImage?) {
        guard let image = image else { return }
        if isRunning { return }
        hasImage = true
        compressionEngine.handleNewImage(image)
    }
    
    func didPressImport() {
        shouldDisplayImport = true
    }
    
    func didChooseImport(_ result: Result<URL, Error>) {
        switch result {
        case.success(let url):
            do {
                let data = try Data(contentsOf: url)
                compressionEngine.importImageWack(fromData: data)
            } catch {
                print(error)
            }
        case.failure(let error):
            print(error)
            return
        }
    }
    
    func didPressExport() {
        guard let data = compressionEngine.createWackImageData() else { return }
        compressionEngine.importImageWack(fromData: data)
        share(data: data, name: imageName + ".data")
    }
    
    func didPressExportPNG() {
        guard let data = compressionEngine.compressedImage.value?.pngData() else { return }
        share(data: data, name: imageName + ".png")
    }
    
    func share(data: Data, name: String) {
        do {
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            guard let root = scene?.windows.first?.rootViewController else { return }
            
            let url = try documentUrlForFile(withName: name, storing: data) 
            let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = root.view
            vc.popoverPresentationController?.sourceRect = bottomBarFrame ?? .zero
            
            root.present(vc, animated: true)
        } catch {
            print(error)
        }
    }
    
}

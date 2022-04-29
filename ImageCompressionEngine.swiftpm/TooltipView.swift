import SwiftUI

enum Edge {
    case left,right,top,bottom
    
    func x(_ geo: GeometryProxy) -> CGFloat {
        let width = geo.size.width
        
        switch self {
        case.top, .bottom:
            return width / 2
        case.left:
            return 0
        case.right:
            return width
        }
    }
    
    func y(_ height: CGFloat) -> CGFloat {
        switch self {
        case.left, .right:
            return 0
        case.top:
            return -height + 4
        case.bottom:
            return height - 4
        }
    }
}

struct TooltipView: View {
    let text: String
    var edge: Edge = .right
    var arrowXPos: CGFloat?=nil
    var shouldDisplay: Binding<Bool>
    @State var shouldFollowXPos: Bool = false
    
    @State var textHeight: CGFloat = 0
    @State var posX: CGFloat = 0
    let background = Color(UIColor.tertiarySystemBackground)
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .foregroundColor(background)
                        .frame(height: textHeight)
                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: 30, height: 30)
                        .rotationEffect(.radians(.pi/4))
                    .position(x: xPosArrow(geo), y: geo.size.height/2 + edge.y(textHeight/2) - 16)
                        .foregroundColor(background)
                }
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 0)
                RoundedRectangle(cornerRadius: 8)
                    .foregroundColor(background)
                    .frame(height: textHeight)
                Text(text)
                    .padding(16)
                    .overlay { 
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: LengthPreference.self, value: geo.size.height)
                        }
                    }
            }.onPreferenceChange(LengthPreference.self) { new in
                self.textHeight = new
            }
                .padding(16)
                .frame(width: width(geo))
                .position(x: transX(geo), y: geo.size.height / 2 - textHeight / 2 - 38 + (edge == .top ? textHeight + 2*38 : 0))
                .onTapGesture {
                    withAnimation {
                        shouldDisplay.wrappedValue = false
                    }
                }
            ZStack {}
                .padding(16)
                .frame(width: width(geo))
                .overlay {
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: LengthPreference.self, value: geo.frame(in: .global).minX)
                    }
                }.onPreferenceChange(LengthPreference.self) { new in
                    self.posX = new
                }
        }
        .transition(.offset(x: 0, y: 20).combined(with: .opacity))
    }
    
    func width(_ geo: GeometryProxy) -> CGFloat {
        return min(400, geo.size.width)
    }
    
    func transX(_ geo: GeometryProxy) -> CGFloat {
        let xPosOff = (shouldFollowXPos ? (arrowXPos ?? 0) - width(geo) / 4 : width(geo) / 2)
        return -posX + xPosOff
    }
    
    func xPosArrow(_ geo: GeometryProxy) -> CGFloat {
        let offset: CGFloat = -6
        let arrPos = (arrowXPos ?? edge.x(geo))
        if shouldFollowXPos {
            return (3 * width(geo) / 4) + offset
        } else {
            return arrPos + offset
        }
    }
}

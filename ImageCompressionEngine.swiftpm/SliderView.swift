//
//  File.swift
//  ImageCompressionEngine
//
//  Created by Eskil Sviggum on 02/04/2022.
//

import SwiftUI

struct SliderView: View {
    let title: String
    let min: Float
    let max: Float
    let unit: String
    let unitScale: Float
    
    @State var value: Float
    @State var valueBinding: Binding<Float>! = .constant(1)
    let handler: ((Float)->Void)?
    let valueTransform: ((Float)->Float)?
    
    init(title: String, unit: String, unitScale: Float = 1, min:Float = 0, max: Float = 1, initial: Float?=nil, handler: ((Float)->Void)?=nil, valueTransform: ((Float)->Float)?=nil) {
        self.title = title
        self.min = min
        self.max = max
        self.unit = unit
        self.unitScale = unitScale
        self.handler = handler
        self.valueTransform = valueTransform
        self.value = initial ?? min
    }
    
    var body: some View {
        HStack {
            Text(title)
                .font(.callout)
            Slider(value: valueBinding, in: min...max)
            Text("\(Int((value * unitScale).rounded())) \(unit)")
        }.onAppear(perform: didAppear)
    }
    
    func didAppear() {
        self.valueBinding = Binding(get: {
            return value
        }, set: { new in
            let val = self.valueTransform?(new) ?? new
            value = val
            handler?(val)
        })
    }
}

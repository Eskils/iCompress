import SwiftUI

struct TooltipText {
    static let luma = 
"""
Luma is the lightness part of the image. Our eyes don’t notice small impurities in places of great detail, so we may throw away detail to save space. The program looks at each row and column of the image as a wave. This makes it possible to find the frequecies which make up the image and remove the high frequencies (which correspond to finer detail).

Threshold determines how many of the frequencies to throw away (greater gives a smaller image), while the segment size determines how large chunks of the image to extract the frequencies from. A greater segment size gives a longer compute time.
"""
    
    static let chroma =
"""
Chroma is the color part of the image. Our eyes do not capture immediate changes in color with great accuracy, so we may store color at a lower resolution to save space. 

Segment size determines how large each color block should be. A greater segment size reduces image size, but may leave the image looking blocky.
"""
    
    static let quantization = 
"""
By using less colors in the image, the program can store a map of all the colors used in the header of the image, then reference the color by number. Using less than 256 colors effectively halves the size of the color-channels.

In some images, reducing the number of colors i barely noticable. In others, the image is left with color-banding. Enabeling dithering may then make the image look better as it distributes noise in the image to reduce banding of color.
"""
    
    static let imageSize = 
"""
The different compression tools make the image easier to compress losslesly (with zip compression). The calculated size is a compressed version of a header, the luma-channel and the chroma-chanel (and a colormap if quantization is enabled).

The reduction percentage is a comparison between the image in jpeg—with quality 100%—and the compressed image. The percentage may therefore be positive, signaling a heavier image. 
"""
    
    static let grayscale = 
"""
Enabeling grayscale keeps the program from storing the colors and therefore heavily reduces the image size.
"""
    
}

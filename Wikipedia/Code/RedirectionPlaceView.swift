import Foundation
import MapKit

class RedirectionPlaceView: MapAnnotation {
 
    public let title: String
    public let identifier: Int
    
    init?(coordinate: CLLocationCoordinate2D, title: String) {
        self.title = title
        self.identifier = RedirectionPlaceView.identifierForTitle(title: title)
        super.init(coordinate: coordinate)
        self.accessibilityLabel = title
    }

    public static func identifierForTitle(title: String) -> Int {
        return title.hash
    }
}

import ballerina/io;
import ballerina/log;
import ballerina/time;
import ballerina/grpc;

listener grpc:Listener ep = new (9090);

final Feature[] & readonly FEATURES = check populateFeature();

@grpc:Descriptor {value: ROUTE_GUIDE_DESC}
isolated service "RouteGuide" on ep {

    private map<RouteNote[]> routeNotesMap = {};

    remote function GetFeature(Point value) returns Feature|error {
        foreach Feature item in FEATURES {
            if item.location == value {
                return item;
            }
        }
        return {location: value, name: ""};
    }

    remote function RecordRoute(stream<Point, grpc:Error?> pointStream) returns RouteSummary|error {
        log:printInfo("RecordRoute called");
        int pointCount = 0;
        int featureCount = 0;
        int distance = 0;
        Point? lastPoint = ();
        decimal startTime = time:monotonicNow();

        check from var point in pointStream
            do {
                pointCount += 1;
                Point streamPoint = point;
                Point? currentLastPoint = lastPoint;
                check from Feature feature in FEATURES
                    do {
                        if feature.location == streamPoint {
                            featureCount += 1;
                        }
                    };
                    
                if currentLastPoint is Point {
                    int calculateDistanceResult = calculateDistance(currentLastPoint, streamPoint);
                    distance += calculateDistanceResult;
                }
                lastPoint = streamPoint;
            };
        decimal endTime = time:monotonicNow();
        return {point_count: pointCount, feature_count: featureCount, distance: distance, elapsed_time: <int>(endTime - startTime)};
    }

    remote function ListFeatures(Rectangle value) returns stream<Feature, error?>|error {
        int left = int:min(value.lo.longitude, value.hi.longitude);
        int right = int:max(value.lo.longitude, value.hi.longitude);
        int top = int:max(value.lo.latitude, value.hi.latitude);
        int bottom = int:min(value.lo.latitude, value.hi.latitude);
        Feature[] features = from Feature item in FEATURES
            where item.name != ""
            where item.location.longitude >= left
            where item.location.longitude <= right
            where item.location.latitude >= bottom
            where item.location.latitude <= top
            select item;
        return features.toStream();
    }

    remote function RouteChat(RouteGuideRouteNoteCaller caller, stream<RouteNote, grpc:Error?> routeNoteStream) returns error? {
        check from var note in routeNoteStream
            do {
                string key = string `${note.location.longitude} ${note.location.latitude}`;
                lock {
                    RouteNote[]? routeNotes = self.routeNotesMap[key];
                    if routeNotes is RouteNote[] {
                        check from var item in routeNotes
                            do {
                                check caller->sendRouteNote(item);
                            };
                        routeNotes.push(note.cloneReadOnly());
                    } else {
                        self.routeNotesMap[key] = [note.cloneReadOnly()];
                    }
                }
            };
    }
}

function populateFeature() returns Feature[] & readonly|error {
    json locationsJson = check io:fileReadJson("resources/route_guide_db.json");
    Feature[] features = check locationsJson.cloneWithType();
    return features.cloneReadOnly();
}

isolated function toRadians(float f) returns float {
    return f * 0.017453292519943295;
}

isolated function calculateDistance(Point p1, Point p2) returns int {
    float cordFactor = 10000000; // 1x(10^7) OR 1e7
    float R = 6371000; // Earth radius in metres
    float lat1 = toRadians(<float>p1.latitude / cordFactor);
    float lat2 = toRadians(<float>p2.latitude / cordFactor);
    float lng1 = toRadians(<float>p1.longitude / cordFactor);
    float lng2 = toRadians(<float>p2.longitude / cordFactor);
    float dlat = lat2 - lat1;
    float dlng = lng2 - lng1;

    float a = 'float:sin(dlat / 2.0) * 'float:sin(dlat / 2.0) + 'float:cos(lat1) * 'float:cos(lat2) * 'float:sin(dlng / 2.0) * 'float:sin(dlng / 2.0);
    float c = 2.0 * 'float:atan2('float:sqrt(a), 'float:sqrt(1.0 - a));
    float distance = R * c;
    return <int>distance;
}

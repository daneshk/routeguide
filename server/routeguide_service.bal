import ballerina/io;
import ballerina/grpc;
import ballerina/time;

listener grpc:Listener ep = new (9090);
final Feature[] & readonly features = check populateFeature();

@grpc:Descriptor {value: ROUTE_GUIDE_DESC}
service "RouteGuide" on ep {

    private map<RouteNote[]> routeNotesMap = {};

    remote function GetFeature(Point value) returns Feature|error {
        foreach Feature feature in features {
            if feature.location == value {
                return feature;
            }
        }
        return {location: value, name: ""};
    }
    remote function RecordRoute(stream<Point, grpc:Error?> pointStream) returns RouteSummary|error {
        int point_count = 0;
        int feature_count = 0;
        int distance = 0;
        decimal startTime = time:monotonicNow();
        Point? lastPoint = ();

        check pointStream.forEach(function(Point p) {
            point_count += 1;
            foreach Feature item in features {
                if item.location == p {
                    feature_count += 1;
                }
            }

            if lastPoint is Point {
                distance += calculateDistance(<Point>lastPoint, p);
            }
            lastPoint = p;
        });
        decimal endTime = time:monotonicNow();
        return {point_count: point_count, feature_count: feature_count, distance: distance, elapsed_time: <int>(endTime - startTime)};
    }

    remote function ListFeatures(Rectangle value) returns stream<Feature, error?>|error {
        int left = int:min(value.lo.latitude, value.hi.latitude);
        int right = int:max(value.lo.latitude, value.hi.latitude);
        int bottom = int:min(value.lo.longitude, value.hi.longitude);
        int top = int:max(value.lo.longitude, value.hi.longitude);

        Feature[] selected = from Feature feature in features
                                where feature.name != ""
                                where feature.location.latitude >= left
                                where feature.location.latitude <= right
                                where feature.location.longitude >= bottom
                                where feature.location.longitude <= top
                                select feature;
        return selected.toStream();
    }
    
    remote function RouteChat(RouteGuideRouteNoteCaller caller, stream<RouteNote, grpc:Error?> clientStream) returns error? {
        check from var note in clientStream
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

function calculateDistance(Point p1, Point p2) returns int {
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

function populateFeature() returns Feature[] & readonly|error {
    json fileReadJson = check io:fileReadJson("./resources/route_guide_db.json");
    Feature[] features = check fileReadJson.cloneWithType();
    return features.cloneReadOnly();
}

function toRadians(float f) returns float {
    return f * 0.017453292519943295;
}
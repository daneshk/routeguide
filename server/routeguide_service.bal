import ballerina/io;
import ballerina/time;
import ballerina/log;
import ballerina/grpc;

listener grpc:Listener ep = new (9090);

@grpc:Descriptor {value: ROUTE_GUIDE_DESC}
service "RouteGuide" on ep {

    final Feature[] & readonly features;
    private map<RouteNote[]> routeNoteMap = {};

    function init() returns error? {
        self.features = check popolateFeatures();
    }

    remote function GetFeature(Point value) returns Feature|error {
        foreach var item in self.features {
            if item.location == value {
                return item;
            }
        }
        return {location: value, name: ""};
    }

    remote function RecordRoute(stream<Point, grpc:Error?> pointStream) returns RouteSummary|error? {
        int point_count = 0;
        int feature_count = 0;
        int distance = 0;
        Point? lastPoint = ();
        decimal startTime = time:monotonicNow();

        grpc:Error? clientError = pointStream.forEach(function(Point point) {
            point_count += 1;

            foreach var item in self.features {
                if item.location == point {
                    feature_count += 1;
                }
            }

            if lastPoint is Point {
                distance += calculateDistance(<Point>lastPoint, point);
            }
            lastPoint = point;
        });
        if clientError is grpc:Error {
            log:printError("client stream ended with an error", 'error = clientError);
            return;
        }

        decimal endTime = time:monotonicNow();
        return {point_count, feature_count, distance, elapsed_time: <int>(endTime - startTime)};
    }

    remote function ListFeatures(Rectangle value) returns stream<Feature, error?>|error {
        int left = int:min(value.lo.longitude, value.hi.longitude);
        int right = int:max(value.lo.longitude, value.hi.longitude);
        int bottom = int:min(value.lo.latitude, value.hi.latitude);
        int top = int:max(value.lo.latitude, value.hi.latitude);

        Feature[] selected = from Feature feature in self.features
            where feature.name != ""
            where feature.location.longitude >= left
            where feature.location.longitude <= right
            where feature.location.latitude >= bottom
            where feature.location.latitude <= top
            select feature;

        return selected.toStream();

    }
    remote function RouteChat(RouteGuideRouteNoteCaller caller, stream<RouteNote, grpc:Error?> clientStream) returns error? {
        error? clientError = from var note in clientStream
            do {
                string key = string `${note.location.latitude} ${note.location.longitude}`;
                lock {
                    RouteNote[]? routeNotes = self.routeNoteMap[key];
                    if routeNotes is RouteNote[] {
                        check from var item in routeNotes
                            do {
                                check caller->sendRouteNote(item);
                            };
                        routeNotes.push(note.cloneReadOnly());
                    } else {
                        self.routeNoteMap[key] = [note.cloneReadOnly()];
                    }
                }
            };
        if clientError is error {
            log:printError("client stream ended with an error", 'error = clientError);
        }
    }
}

function popolateFeatures() returns Feature[] & readonly|error {
    json fileReadJson = check io:fileReadJson("./resources/route_guide_db.json");
    Feature[] features = check fileReadJson.cloneWithType();
    return features.cloneReadOnly();
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

function toRadians(float f) returns float {
    return f * 0.017453292519943295;
}

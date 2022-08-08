import ballerina/grpc;
import ballerina/io;
RouteGuideClient ep = check new ("http://localhost:9090");

public function main() returns error? {
    Point point = {
        latitude: 407838351,
        longitude: -746143763
    };
    Feature feature = check ep->GetFeature(point);
    io:println(`Get Feature name: ${feature.name}`);

    Point[] points = [{
        latitude: 407838351,
        longitude: -746143763
    }, {
        latitude: 407588351,
        longitude: -746143763
    }];

    RecordRouteStreamingClient recordRouteClient = check ep->RecordRoute();
    foreach Point item in points {
        _ = check recordRouteClient->sendPoint(item);      
    }
    _ = check recordRouteClient->complete();

    RouteSummary? receiveRouteSummary = check recordRouteClient->receiveRouteSummary();

    if receiveRouteSummary is RouteSummary {
        io:println(`Finished trip with: ${receiveRouteSummary.point_count} points, ${receiveRouteSummary.feature_count} features, ${receiveRouteSummary.distance} meters, and ${receiveRouteSummary.elapsed_time} seconds`);
    }

    Rectangle rectangle = {
        lo: {
            latitude: 400000000,
            longitude: -750000000
        },
        hi: {
            latitude: 500000000,
            longitude: -730000000
        }
    };

    stream<Feature, grpc:Error?> listFeatures = check ep->ListFeatures(rectangle);
    check listFeatures.forEach(function (Feature f) {
        io:println(`Feature name: ${f.name}`);
    });

    RouteNote[] routeNotes = [
        {location: {latitude: 406109563, longitude: -742186778}, message: "m1"}, 
        {location: {latitude: 411733222, longitude: -744228360}, message: "m2"}, 
        {location: {latitude: 406109563, longitude: -742186778}, message: "m3"}, 
        {location: {latitude: 411733222, longitude: -744228360}, message: "m4"}, 
        {location: {latitude: 411733222, longitude: -744228360}, message: "m5"}
    ];


    RouteChatStreamingClient routeChat = check ep->RouteChat();

    future<error?> f1 = start readResponse(routeChat);
    foreach RouteNote item in routeNotes {
        _ = check routeChat->sendRouteNote(item);
    }
    check routeChat->complete();
    check wait f1;
}

function readResponse(RouteChatStreamingClient routeClient) returns error? {
     RouteNote? receiveRouteNote = check routeClient->receiveRouteNote();
     while receiveRouteNote != () {
         io:println(`Got message '${receiveRouteNote.message}' at lat=${receiveRouteNote.location.latitude},
                lon=${receiveRouteNote.location.longitude}`);
         receiveRouteNote = check routeClient->receiveRouteNote();
     }
}
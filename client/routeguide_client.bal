import ballerina/grpc;
import ballerina/io;

RouteGuideClient ep = check new ("http://192.168.1.30:30373");

public function main() returns error? {
    Point request = {
        latitude: 407838351,
        longitude: -746143763
    };
    Feature response = check ep->GetFeature(request);
    io:println(`Get Feature name: ${response.name}`);

    Rectangle rectangle = {
        hi: {
            latitude: 400000000,
            longitude: -750000000
        },
        lo: {
            latitude: 500000000,
            longitude: -730000000
        }
    };

    stream<Feature, grpc:Error?> listFeatures = check ep->ListFeatures(rectangle);
    check listFeatures.forEach(function (Feature feature){
        io:println(`Feature name: ${feature.name}`);
    });

    Point[] points = [{
        latitude: 407838351,
        longitude: -746143763
    }, {
        latitude: 500000000,
        longitude: -730000000
    }];

    RecordRouteStreamingClient recordRouteClient = check ep->RecordRoute();
    foreach var item in points {
        check recordRouteClient->sendPoint(item);       
    }
    check recordRouteClient->complete();

    RouteSummary? receiveRouteSummary = check recordRouteClient->receiveRouteSummary();
    if receiveRouteSummary is RouteSummary {
        io:println(`Finished trip with: ${receiveRouteSummary.point_count} points, ${receiveRouteSummary.feature_count} features, ${receiveRouteSummary.distance} meters, and ${receiveRouteSummary.elapsed_time} seconds`);
    }

    RouteNote[] routeNotes = [
        {location: {latitude: 406109563, longitude: -742186778}, message: "m1"}, 
        {location: {latitude: 411733222, longitude: -744228360}, message: "m2"}, 
        {location: {latitude: 406109563, longitude: -742186778}, message: "m3"}, 
        {location: {latitude: 411733222, longitude: -744228360}, message: "m4"}, 
        {location: {latitude: 411733222, longitude: -744228360}, message: "m5"}
    ];

    RouteChatStreamingClient routeChatClient = check ep->RouteChat();
    future<error?> f1 = start readResponse(routeChatClient);

    foreach var item in routeNotes {
        check routeChatClient->sendRouteNote(item);
    }
    check routeChatClient->complete();
    check wait f1;
}

function readResponse(RouteChatStreamingClient routeChatClient) returns error? {
    RouteNote? receiveRouteNote = check routeChatClient->receiveRouteNote();
    while receiveRouteNote is RouteNote {
        io:println(`Got message '${receiveRouteNote.message}' at lat=${receiveRouteNote.location.latitude},
                lon=${receiveRouteNote.location.longitude}`);
        receiveRouteNote = check routeChatClient->receiveRouteNote();        
    }
}

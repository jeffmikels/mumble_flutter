import './mumble.pb.dart' as mpb;

class MumbleChannel {
  int id;
  int parent;

  String name;
  String path;

  List<int> links = [];
  String description;
  bool temporary;
  int position;

  mpb.ChannelState pb;

  MumbleChannel(this.pb) {
    links = [];
    updateFromProto(pb);
  }

  void updateFromProto(mpb.ChannelState pb) {
    this.pb = pb;
    id = pb.channelId;
    parent = pb.parent;
    name = pb.name;
    description = pb.description;
    temporary = pb.temporary;
    position = pb.position;

    links.addAll(pb.links);
    links.addAll(pb.linksAdd);
    for (var i in pb.linksRemove) {
      links.remove(i);
    }
  }
}

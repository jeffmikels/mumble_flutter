import './mumble.pb.dart' as mpb;

class MumbleChannel {
  mpb.ChannelState pb;

  int id;
  int parent;
  int position;
  bool temporary = false;

  String name = '';
  String description = '';
  String path = '';

  List<int> links = [];

  MumbleChannel(this.pb) {
    links = [];
    updateFromProto(pb);
  }

  void updateFromProto(mpb.ChannelState pb) {
    this.pb = pb;
    id = pb.channelId ?? id;
    parent = pb.parent ?? parent;
    position = pb.position ?? position;
    temporary = pb.temporary ?? temporary;

    name = pb.name.isNotEmpty ? pb.name : name;
    description = pb.description.isNotEmpty ? pb.description : description;

    links.addAll(pb.links);
    links.addAll(pb.linksAdd);
    for (var i in pb.linksRemove) {
      links.remove(i);
    }
  }
}

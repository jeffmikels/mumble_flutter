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
    id = pb.hasChannelId() ? pb.channelId : id;
    parent = pb.hasParent() ? pb.parent : parent;
    position = pb.hasPosition() ? pb.position : position;
    temporary = pb.hasTemporary() ? pb.temporary : temporary;

    name = pb.hasName() ? pb.name : name;
    description = pb.hasDescription() ? pb.description : description;

    links.addAll(pb.links);
    links.addAll(pb.linksAdd);
    for (var i in pb.linksRemove) {
      links.remove(i);
    }
  }
}

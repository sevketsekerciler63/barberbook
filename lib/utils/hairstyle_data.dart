class HairstyleModel {
  final String id;
  final String name;
  final String imagePath;

  const HairstyleModel({
    required this.id,
    required this.name,
    required this.imagePath,
  });
}

class HairstyleData {
  static const List<HairstyleModel> hairstyles = [
    HairstyleModel(
      id: 'skin_fade',
      name: 'Skin Fade',
      imagePath: 'assets/hairstyles/skin_fade.jpg',
    ),
    HairstyleModel(
      id: 'mid_fade',
      name: 'Mid Fade',
      imagePath: 'assets/hairstyles/mid_fade.jpg',
    ),
    HairstyleModel(
      id: 'high_fade',
      name: 'High Fade',
      imagePath: 'assets/hairstyles/high_fade.jpg',
    ),
    HairstyleModel(
      id: 'undercut',
      name: 'Undercut',
      imagePath: 'assets/hairstyles/undercut.jpg',
    ),
    HairstyleModel(
      id: 'buzz_cut',
      name: 'Buzz Cut',
      imagePath: 'assets/hairstyles/buzz_cut.jpg',
    ),
    HairstyleModel(
      id: 'pompadour',
      name: 'Pompadour',
      imagePath: 'assets/hairstyles/pompadour.jpg',
    ),
    HairstyleModel(
      id: 'crew_cut',
      name: 'Crew Cut',
      imagePath: 'assets/hairstyles/crew_cut.jpg',
    ),
    HairstyleModel(
      id: 'quiff',
      name: 'Quiff',
      imagePath: 'assets/hairstyles/quiff.jpg',
    ),
    HairstyleModel(
      id: 'slick_back',
      name: 'Slick Back',
      imagePath: 'assets/hairstyles/slick_back.jpg',
    ),
    HairstyleModel(
      id: 'textured_crop',
      name: 'Textured Crop',
      imagePath: 'assets/hairstyles/textured_crop.jpg',
    ),
    HairstyleModel(
      id: 'faux_hawk',
      name: 'Faux Hawk',
      imagePath: 'assets/hairstyles/faux_hawk.jpg',
    ),
  ];

  static HairstyleModel? getById(String id) {
    try {
      return hairstyles.firstWhere((h) => h.id == id);
    } catch (_) {
      return null;
    }
  }
}

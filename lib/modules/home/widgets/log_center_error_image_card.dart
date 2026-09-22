part of 'log_center_panel.dart';

/// Error detail image preview with an action-aware download button.
class LogCenterErrorImageCard extends StatelessWidget {
  /// Creates one error image card.
  const LogCenterErrorImageCard({
    super.key,
    required this.controller,
    required this.detail,
    required this.image,
  });

  /// Log browser controller.
  final ScriptLogBrowserController controller;

  /// Error detail owning the image.
  final ScriptErrorLogDetail detail;

  /// Image metadata rendered by this card.
  final ScriptErrorImageInfo image;

  @override
  Widget build(BuildContext context) {
    final url = ApiClient().buildScriptErrorImageUrl(detail.id, image.name);
    return SizedBox(
      width: 140,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildPreview(url), _buildDownloadButton()],
      ),
    );
  }

  /// Builds the async network image preview.
  Widget _buildPreview(String url) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.xs),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) {
              return child;
            }
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) {
            return const Center(child: Icon(Icons.broken_image_outlined));
          },
        ),
      ),
    );
  }

  /// Builds the per-image download button with loading feedback.
  Widget _buildDownloadButton() {
    return Obx(() {
      final loading = controller.isErrorImageDownloading(image);
      return IconButton(
        tooltip: I18n.homeLogDownloadImage.tr,
        onPressed: loading ? null : () => controller.downloadErrorImage(image),
        icon: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download_rounded),
      );
    });
  }
}

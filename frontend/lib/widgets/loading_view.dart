import 'package:flutter/material.dart';

enum LoadingType { list, grid, card }

class LoadingView extends StatefulWidget {
  final LoadingType type;
  final int itemCount;
  final int crossAxisCount;

  const LoadingView({
    super.key,
    this.type = LoadingType.list,
    this.itemCount = 6,
    this.crossAxisCount = 2,
  });

  @override
  State<LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<LoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final highlightColor = colorScheme.surfaceContainerHighest;
    final baseColor = colorScheme.surfaceContainerLow;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final gradient = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [baseColor, highlightColor, baseColor],
          stops: const [0.0, 0.5, 1.0],
        );

        switch (widget.type) {
          case LoadingType.list:
            return _buildListShimmer(gradient);
          case LoadingType.grid:
            return _buildGridShimmer(gradient);
          case LoadingType.card:
            return _buildCardShimmer(gradient);
        }
      },
    );
  }

  Widget _shimmerContainer(LinearGradient gradient, Widget child) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(bounds),
      blendMode: BlendMode.srcATop,
      child: child,
    );
  }

  Widget _buildListShimmer(LinearGradient gradient) {
    final cs = Theme.of(context).colorScheme;
    return _shimmerContainer(
      gradient,
      ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: widget.itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          return Container(
            height: 72,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGridShimmer(LinearGradient gradient) {
    final cs = Theme.of(context).colorScheme;
    return _shimmerContainer(
      gradient,
      GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.crossAxisCount,
          childAspectRatio: 1.2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: widget.itemCount,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardShimmer(LinearGradient gradient) {
    final cs = Theme.of(context).colorScheme;
    return _shimmerContainer(
      gradient,
      ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(widget.itemCount, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }),
      ),
    );
  }
}

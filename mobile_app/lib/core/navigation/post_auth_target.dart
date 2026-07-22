String resolvePostAuthTarget(String? next) {
  if (next == null || next.trim().isEmpty) return '/locations';

  final uri = Uri.tryParse(next);
  if (uri == null) return '/locations';

  final path = uri.path;

  final blockedPaths = {
    '/',
    '/info',
    '/login',
    '/signup',
    '/privacy',
    '/privacy-preview',
    '/terms',
    '/terms-preview',
    '/password-reset',
    '/password-reset/sent',
  };

  if (blockedPaths.contains(path)) return '/locations';
  if (path.startsWith('/signup')) return '/locations';
  if (!path.startsWith('/')) return '/locations';

  return next;
}

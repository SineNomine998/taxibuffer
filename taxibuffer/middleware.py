from django.conf import settings
from django.shortcuts import redirect

# TODO! Check this in more detail!
class DomainRedirectMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        host = request.get_host().split(':')[0]  # Remove port if present
        
        # For development environment testing
        if settings.DEBUG and host in ['localhost', '127.0.0.1']:
            return self.get_response(request)
            
        # Handle control domain
        if host == settings.CONTROL_DOMAIN:
            if not request.path.startswith('/control/') and not request.path.startswith('/admin/'):
                return redirect('/control/')
        
        # Handle main domain
        elif host == settings.MAIN_DOMAIN:
            if request.path.startswith('/control/'):
                return redirect('/queueing/')
        
        return self.get_response(request)
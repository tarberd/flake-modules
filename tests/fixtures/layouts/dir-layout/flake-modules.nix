{ mkFlakeModule, ... }: mkFlakeModule { public = [ ./alice ]; } { rootMarker = "root"; }

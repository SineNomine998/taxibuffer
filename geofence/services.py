from django.contrib.gis.geos import Point, GEOSGeometry
import logging

logger = logging.getLogger(__name__)

def make_point_from_lat_lng(latitude: float, longitude: float, srid: int = 4326) -> Point:
    """Return a Point(lon, lat) with the requested SRID."""
    p = Point(longitude, latitude, srid=srid)
    return p

def point_in_buffer(buffer_zone, latitude: float, longitude: float, inclusive: bool = True) -> bool:
    """
    Return True if (lat,lng) is inside the buffer_zone, which is a polygon.

    - buffer_zone: BufferZone instance with `zone` PolygonField
    - inclusive: if True uses intersects() (boundary counts), else contains() (boundary does not count)
    """
    if buffer_zone is None or buffer_zone.zone is None:
        logger.debug("No buffer zone geometry present.")
        return False

    p = make_point_from_lat_lng(latitude, longitude, srid=4326)

    try:
        zone_srid = getattr(buffer_zone.zone, "srid", None) or 4326
        if p.srid != zone_srid:
            geo = GEOSGeometry(p.wkt, srid=p.srid)
            geo.transform(zone_srid)
            p = geo
    except Exception:
        logger.exception("Failed to transform point to zone SRID")

    try:
        if inclusive:
            return buffer_zone.zone.intersects(p)
        else:
            return buffer_zone.zone.contains(p)
    except Exception:
        logger.exception("Spatial check failed; denying by default")
        return False

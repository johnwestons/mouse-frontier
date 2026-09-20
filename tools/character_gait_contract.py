"""Shared offline run framing contract; does not grant visual acceptance."""
RUN_PHASES = [
    'left_contact', 'left_load', 'flight_right_swing', 'right_reach',
    'right_contact', 'right_load', 'flight_left_swing', 'left_reach',
]


def run_ground_clearance(value, frame_size=512):
    """Pixel clearance above the fixed ground anchor, including reach/flight.

    Contact/loading must remain planted. Both half-cycles must agree; arbitrary
    per-frame baseline waivers, negative clearance and excessive flight fail.
    """
    if (not isinstance(value, list) or len(value) != 8
            or any(type(v) is not int or not 0 <= v <= frame_size * .05 for v in value)
            or any(value[i] != 0 for i in (0, 1, 4, 5))
            or any(value[i] <= 0 for i in (2, 3, 6, 7))
            or value[:4] != value[4:]):
        raise ValueError('run ground_clearance requires eight symmetric integer clearances: '
                         'zero at contact/load, positive and at most 5% of frame height at flight/reach')
    return list(value)


def locomotion_sources(manifest):
    walks, runs = manifest.get('walks', {}), manifest.get('runs', {})
    if not isinstance(walks, dict) or not isinstance(runs, dict):
        raise ValueError('walks and runs must be objects')
    if set(walks) & set(runs):
        raise ValueError('walk/run output names must not overlap')
    return {**walks, **runs}

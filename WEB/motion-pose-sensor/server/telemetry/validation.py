import math
import uuid


class PayloadError(ValueError):
    def __init__(self, field, message):
        self.field = field
        self.message = message
        super().__init__(f"{field}: {message}")


def object_at(value, field):
    if not isinstance(value, dict):
        raise PayloadError(field, "必須是 JSON 物件")
    return value


def integer_at(value, field, minimum=0):
    if type(value) is not int or value < minimum or value > 9223372036854775807:
        raise PayloadError(field, f"必須是介於 {minimum} 與 2^63-1 的整數")
    return value


def number_at(value, field, minimum=None, maximum=None):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise PayloadError(field, "必須是有限數字")
    if (minimum is not None and value < minimum) or (maximum is not None and value > maximum):
        raise PayloadError(field, f"必須介於 {minimum} 與 {maximum}")
    return value


def numeric_group(value, field, keys):
    group = object_at(value, field)
    return {key: number_at(group.get(key), f"{field}.{key}") for key in keys}


def validate(payload):
    payload = object_at(payload, "body")
    if type(payload.get("schema_version")) is not int or payload["schema_version"] != 1:
        raise PayloadError("schema_version", "目前只支援整數 1")
    raw_id = payload.get("device_id")
    try:
        if not isinstance(raw_id, str):
            raise ValueError
        device_id = uuid.UUID(raw_id)
    except ValueError:
        raise PayloadError("device_id", "必須是有效的 UUID 字串") from None
    kind = payload.get("device_kind")
    if kind not in ("iphone", "ipad"):
        raise PayloadError("device_kind", "必須是 iphone 或 ipad")
    sample_type = payload.get("type")
    if sample_type not in ("motion", "body_pose"):
        raise PayloadError("type", "必須是 motion 或 body_pose")
    timestamp_ms = integer_at(payload.get("timestamp_ms"), "timestamp_ms")

    result = {"device_id": device_id, "device_kind": kind, "type": sample_type,
              "timestamp_ms": timestamp_ms, "motion": None, "body_pose": None}
    if sample_type == "motion":
        motion = object_at(payload.get("motion"), "motion")
        fields = {
            "position_m": ("x", "y", "z"),
            "attitude_deg": ("roll", "pitch", "yaw"),
            "angular_velocity_deg_s": ("x", "y", "z"),
        }
        cleaned = {key: numeric_group(motion[key], f"motion.{key}", axes)
                   for key, axes in fields.items() if key in motion}
        if not ("position_m" in cleaned or "attitude_deg" in cleaned):
            raise PayloadError("motion", "至少須有 position_m 或 attitude_deg")
        result["motion"] = cleaned
    else:
        pose = object_at(payload.get("body_pose"), "body_pose")
        if pose.get("coordinate_system") != "normalized_image_bottom_left":
            raise PayloadError("body_pose.coordinate_system", "必須是 normalized_image_bottom_left")
        cleaned = {"coordinate_system": pose["coordinate_system"]}
        if "image_size_px" in pose:
            size = object_at(pose["image_size_px"], "body_pose.image_size_px")
            cleaned["image_size_px"] = {
                key: integer_at(size.get(key), f"body_pose.image_size_px.{key}", 1)
                for key in ("width", "height")
            }
        joints = object_at(pose.get("joints"), "body_pose.joints")
        cleaned_joints = {}
        for name, joint in joints.items():
            if not isinstance(name, str) or not name:
                raise PayloadError("body_pose.joints", "關節名稱必須是非空字串")
            point = object_at(joint, f"body_pose.joints.{name}")
            cleaned_joints[name] = {
                key: number_at(point.get(key), f"body_pose.joints.{name}.{key}", 0, 1)
                for key in ("x", "y", "confidence")
            }
        cleaned["joints"] = cleaned_joints
        result["body_pose"] = cleaned
    return result

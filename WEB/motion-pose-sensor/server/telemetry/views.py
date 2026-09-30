import json
import uuid

from django.db import transaction
from django.db.models import Exists, OuterRef
from django.http import JsonResponse
from django.shortcuts import render
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt

from .models import Device, TelemetrySample
from .validation import PayloadError, validate


def error(field, message, status=400):
    return JsonResponse({"error": {"field": field, "message": message}}, status=status)


def sample_json(sample):
    if sample is None:
        return None
    data = {
        "id": sample.pk,
        "device_id": str(sample.device_id),
        "device_kind": sample.device.device_kind,
        "type": sample.type,
        "timestamp_ms": sample.timestamp_ms,
        "received_at": sample.received_at.isoformat(),
    }
    data[sample.type] = sample.motion if sample.type == "motion" else sample.body_pose
    return data


def device_json(device):
    return {
        "device_id": str(device.device_id),
        "device_kind": device.device_kind,
        "last_seen_at": device.last_seen_at.isoformat(),
        "last_timestamp_ms": device.last_timestamp_ms,
    }


def find_device(device_id):
    try:
        parsed_id = uuid.UUID(device_id)
    except ValueError:
        return None
    return Device.objects.filter(pk=parsed_id).first()


@csrf_exempt
def telemetry_ingest(request):
    if request.method != "POST":
        return error("method", "只接受 POST", 405)
    if request.content_type != "application/json":
        return error("content_type", "必須是 application/json")
    try:
        payload = json.loads(request.body)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return error("body", "必須是有效的 JSON")
    try:
        data = validate(payload)
    except PayloadError as exc:
        return error(exc.field, exc.message)

    with transaction.atomic():
        device, created = Device.objects.get_or_create(
            device_id=data["device_id"],
            defaults={"device_kind": data["device_kind"], "last_seen_at": timezone.now(),
                      "last_timestamp_ms": data["timestamp_ms"]},
        )
        if not created:
            device.device_kind = data["device_kind"]
            device.last_seen_at = timezone.now()
            device.last_timestamp_ms = max(device.last_timestamp_ms, data["timestamp_ms"])
            device.save(update_fields=["device_kind", "last_seen_at", "last_timestamp_ms"])
        sample = TelemetrySample.objects.create(
            device=device, type=data["type"], timestamp_ms=data["timestamp_ms"],
            motion=data["motion"], body_pose=data["body_pose"],
        )
    return JsonResponse({"ok": True, "id": sample.pk}, status=201)


def devices(request):
    if request.method != "GET":
        return error("method", "只接受 GET", 405)
    samples = TelemetrySample.objects.filter(device_id=OuterRef("pk"))
    queryset = Device.objects.annotate(
        has_motion=Exists(samples.filter(type="motion")),
        has_body_pose=Exists(samples.filter(type="body_pose")),
    ).order_by("-last_seen_at")
    return JsonResponse({"devices": [
        {**device_json(d), "available_types": [
            sample_type for sample_type, present in (
                ("motion", d.has_motion), ("body_pose", d.has_body_pose)
            ) if present
        ]} for d in queryset
    ]})


def latest(request, device_id):
    if request.method != "GET":
        return error("method", "只接受 GET", 405)
    device = find_device(device_id)
    if device is None:
        return error("device_id", "找不到裝置", 404)
    samples = {}
    for sample_type in ("motion", "body_pose"):
        sample = device.samples.filter(type=sample_type).order_by("-timestamp_ms", "-id").first()
        samples[sample_type] = sample_json(sample)
    return JsonResponse({"device": device_json(device), "latest": samples})


def query_integer(request, name, minimum, maximum):
    raw = request.GET.get(name)
    try:
        if raw is None or not raw.isdecimal():
            raise ValueError
        value = int(raw)
    except ValueError:
        raise PayloadError(name, f"必須是 {minimum} 到 {maximum} 的整數") from None
    if not minimum <= value <= maximum:
        raise PayloadError(name, f"必須是 {minimum} 到 {maximum} 的整數")
    return value


def history(request, device_id):
    if request.method != "GET":
        return error("method", "只接受 GET", 405)
    device = find_device(device_id)
    if device is None:
        return error("device_id", "找不到裝置", 404)
    try:
        start_ms = query_integer(request, "start_ms", 0, 9223372036854775807)
        end_ms = query_integer(request, "end_ms", 0, 9223372036854775807)
        limit = query_integer(request, "limit", 1, 2000) if "limit" in request.GET else 1000
        if start_ms > end_ms:
            raise PayloadError("start_ms", "不得晚於 end_ms")
        sample_type = request.GET.get("type", "motion")
        if sample_type not in ("motion", "body_pose"):
            raise PayloadError("type", "必須是 motion 或 body_pose")
    except PayloadError as exc:
        return error(exc.field, exc.message)
    queryset = device.samples.select_related("device").filter(
        type=sample_type, timestamp_ms__gte=start_ms, timestamp_ms__lte=end_ms
    ).order_by("-timestamp_ms", "-id")[:limit]
    samples = list(queryset)
    samples.reverse()
    return JsonResponse({"device_id": str(device.device_id), "type": sample_type,
                         "start_ms": start_ms, "end_ms": end_ms,
                         "limit": limit, "samples": [sample_json(s) for s in samples]})


def dashboard(request):
    return render(request, "telemetry/dashboard.html")

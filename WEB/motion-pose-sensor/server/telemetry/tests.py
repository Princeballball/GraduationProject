import json

from django.test import Client, TestCase

from .models import Device, TelemetrySample


PHONE = "A4EDB664-7198-4C7E-901B-056D57BB593B"
TABLET = "5B477491-5CB8-4601-8960-66052E099AA5"


def motion_payload(device_id=PHONE, timestamp=1000):
    return {
        "schema_version": 1, "device_id": device_id, "device_kind": "iphone",
        "type": "motion", "timestamp_ms": timestamp,
        "motion": {
            "position_m": {"x": 0.12, "y": 0.35, "z": -0.04},
            "attitude_deg": {"roll": 2.1, "pitch": -8.5, "yaw": 12.3},
            "angular_velocity_deg_s": {"x": 0.4, "y": -1.7, "z": 0.2},
        },
    }


def pose_payload(joints=None, timestamp=1000):
    return {
        "schema_version": 1, "device_id": TABLET, "device_kind": "ipad",
        "type": "body_pose", "timestamp_ms": timestamp,
        "body_pose": {
            "coordinate_system": "normalized_image_bottom_left",
            "image_size_px": {"width": 1280, "height": 720},
            "joints": joints if joints is not None else {
                "VNHumanBodyPoseObservationJointNameLeftShoulder": {
                    "x": 0.42, "y": 0.71, "confidence": 0.93,
                },
            },
        },
    }


class TelemetryTests(TestCase):
    def post_payload(self, payload):
        return self.client.post("/api/telemetry/", data=json.dumps(payload), content_type="application/json")

    def test_motion_saved_with_all_values(self):
        response = self.post_payload(motion_payload())
        self.assertEqual(response.status_code, 201)
        sample = TelemetrySample.objects.get()
        self.assertEqual(sample.device_id.hex.upper(), PHONE.replace("-", ""))
        self.assertEqual(sample.motion["attitude_deg"]["pitch"], -8.5)
        self.assertIsNone(sample.body_pose)
        self.assertEqual(Device.objects.count(), 1)

    def test_optional_motion_fields_can_be_missing(self):
        payload = motion_payload()
        payload["motion"] = {"position_m": {"x": 1, "y": 2, "z": 3}}
        self.assertEqual(self.post_payload(payload).status_code, 201)
        self.assertEqual(TelemetrySample.objects.get().motion, payload["motion"])

    def test_pose_and_empty_joints_clear_latest(self):
        self.assertEqual(self.post_payload(pose_payload()).status_code, 201)
        self.assertEqual(self.post_payload(pose_payload({}, 1001)).status_code, 201)
        response = self.client.get(f"/api/devices/{TABLET}/latest/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["latest"]["body_pose"]["body_pose"]["joints"], {})
        self.assertIsNone(response.json()["latest"]["motion"])

    def test_pose_without_image_size(self):
        payload = pose_payload({})
        del payload["body_pose"]["image_size_px"]
        self.assertEqual(self.post_payload(payload).status_code, 201)

    def test_invalid_payloads_name_field_and_do_not_save(self):
        cases = [
            ({**motion_payload(), "schema_version": 2}, "schema_version"),
            ({**motion_payload(), "device_id": "not-a-uuid"}, "device_id"),
            ({**motion_payload(), "timestamp_ms": True}, "timestamp_ms"),
            ({**motion_payload(), "motion": {}}, "motion"),
            ({**motion_payload(), "motion": {"position_m": {"x": 1, "y": 2}}}, "motion.position_m.z"),
            ({**motion_payload(), "motion": {"attitude_deg": {"roll": float("nan"), "pitch": 0, "yaw": 0}}}, "motion.attitude_deg.roll"),
            ({**pose_payload(), "body_pose": {**pose_payload()["body_pose"], "coordinate_system": "top_left"}}, "body_pose.coordinate_system"),
        ]
        bad_joint = pose_payload()
        bad_joint["body_pose"]["joints"]["VNHumanBodyPoseObservationJointNameLeftShoulder"]["x"] = 1.1
        cases.append((bad_joint, "body_pose.joints.VNHumanBodyPoseObservationJointNameLeftShoulder.x"))
        for payload, field in cases:
            with self.subTest(field=field):
                response = self.post_payload(payload)
                self.assertEqual(response.status_code, 400)
                self.assertEqual(response.json()["error"]["field"], field)
        self.assertEqual(TelemetrySample.objects.count(), 0)

    def test_invalid_json_and_content_type(self):
        response = self.client.post("/api/telemetry/", "{oops", content_type="application/json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["field"], "body")
        response = self.client.post("/api/telemetry/", "{}", content_type="text/plain")
        self.assertEqual(response.json()["error"]["field"], "content_type")

    def test_native_post_does_not_require_csrf_cookie(self):
        strict_client = Client(enforce_csrf_checks=True)
        response = strict_client.post("/api/telemetry/", data=json.dumps(motion_payload()),
                                      content_type="application/json")
        self.assertEqual(response.status_code, 201)

    def test_native_post_without_trailing_slash(self):
        strict_client = Client(enforce_csrf_checks=True)
        response = strict_client.post("/api/telemetry", data=json.dumps(motion_payload()),
                                      content_type="application/json")
        self.assertEqual(response.status_code, 201)
        self.assertEqual(TelemetrySample.objects.count(), 1)

    def test_device_isolation_and_history_range_and_limit(self):
        for timestamp in (1000, 2000, 3000, 4000):
            self.post_payload(motion_payload(timestamp=timestamp))
        other = motion_payload(device_id=TABLET, timestamp=2500)
        other["device_kind"] = "ipad"
        self.post_payload(other)
        self.post_payload(pose_payload({}, 2500))
        devices = self.client.get("/api/devices/").json()["devices"]
        self.assertEqual(len(devices), 2)
        types_by_id = {d["device_id"]: d["available_types"] for d in devices}
        self.assertEqual(types_by_id[PHONE.lower()], ["motion"])
        self.assertEqual(types_by_id[TABLET.lower()], ["motion", "body_pose"])
        response = self.client.get(f"/api/devices/{PHONE}/history/",
                                   {"start_ms": 1500, "end_ms": 4000, "limit": 2})
        self.assertEqual(response.status_code, 200)
        self.assertEqual([s["timestamp_ms"] for s in response.json()["samples"]], [3000, 4000])
        self.assertTrue(all(s["device_id"] == PHONE.lower() for s in response.json()["samples"]))
        response = self.client.get(f"/api/devices/{TABLET}/history/",
                                   {"start_ms": 0, "end_ms": 4000, "type": "body_pose"})
        self.assertEqual(len(response.json()["samples"]), 1)
        latest = self.client.get(f"/api/devices/{PHONE}/latest/").json()["latest"]
        self.assertEqual(latest["motion"]["timestamp_ms"], 4000)

    def test_history_rejects_unbounded_or_bad_range(self):
        self.post_payload(motion_payload())
        for params, field in [({}, "start_ms"),
                              ({"start_ms": 2000, "end_ms": 1000}, "start_ms"),
                              ({"start_ms": 0, "end_ms": 9999, "limit": 2001}, "limit"),
                              ({"start_ms": 0, "end_ms": 9999, "type": "bad"}, "type")]:
            with self.subTest(params=params):
                response = self.client.get(f"/api/devices/{PHONE}/history/", params)
                self.assertEqual(response.status_code, 400)
                self.assertEqual(response.json()["error"]["field"], field)

    def test_dashboard_page(self):
        response = self.client.get("/dashboard/")
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "即時 Telemetry")
        self.assertContains(response, "畫面 1")
        self.assertContains(response, "畫面 2")
        self.assertContains(response, "顯示內容")
        self.assertContains(response, "即時設備")
        self.assertContains(response, "暫停畫面")

    def test_root_redirects_to_dashboard(self):
        response = self.client.get("/")
        self.assertRedirects(response, "/dashboard/")

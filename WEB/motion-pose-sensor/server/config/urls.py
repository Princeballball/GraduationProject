from django.urls import path
from django.views.generic import RedirectView

from telemetry import views

urlpatterns = [
    path("", RedirectView.as_view(pattern_name="dashboard", permanent=False), name="home"),
    path("api/telemetry", views.telemetry_ingest, name="telemetry-ingest-no-slash"),
    path("api/telemetry/", views.telemetry_ingest, name="telemetry-ingest"),
    path("api/devices/", views.devices, name="devices"),
    path("api/devices/<str:device_id>/latest/", views.latest, name="latest"),
    path("api/devices/<str:device_id>/history/", views.history, name="history"),
    path("dashboard/", views.dashboard, name="dashboard"),
]

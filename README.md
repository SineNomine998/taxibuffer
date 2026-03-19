# TaxiBuffer

TaxiBuffer is a Django-based taxi queue coordination system. It helps move chauffeurs from buffer zones to pickup zones in a controlled way, with queue status tracking, officer monitoring, and sensor-driven pickup occupancy updates. 

You can visit the site [taxibuffer.nl](https://taxibuffer.nl/) to see the latest version in production.

## Core Functionality

- Chauffeur intake flow (login, location selection, queue join).
- Queue lifecycle with statuses such as waiting, notified, and dequeued.
- Officer control panel to monitor queues and manage queue behavior.
- Sensor ingestion endpoint to track pickup occupancy.
- Support for push subscription records tied to queue entries.

## Tech Stack

- Python + Django 5.2
- Postgres with PostGIS backend
- Django apps: `accounts`, `geofence`, `queueing`, `sensors`, `control_panel`
- Optional API/JWT-related dependencies are included in `requirements.txt`

## Project Structure

- `taxibuffer/` (project root)
- `taxibuffer/settings.py` configuration
- `accounts/` user, chauffeur, and officer models
- `geofence/` buffer/pickup zones and geo-related logic
- `queueing/` queue models, services, views, management commands
- `sensors/` sensor devices, readings, and ingestion endpoint
- `control_panel/` officer-facing dashboard and queue monitor

## Prerequisites

- Python 3.11+ (recommended)
- PostgreSQL with PostGIS extension enabled
- `pip` and virtual environment support

## Environment Variables

Create a `.env` file in the project root (`taxibuffer/.env`) with at least:

```env
SECRET_KEY=change-me

DATABASE_NAME=taxibuffer
DATABASE_USER=postgres
DATABASE_PASSWORD=postgres
DATABASE_HOST=127.0.0.1
DATABASE_PORT=5432

VAPID_PUBLIC_KEY=your-public-key
VAPID_PRIVATE_KEY=your-private-key
```

Notes:

- Settings are loaded with `python-decouple`.
- Database engine is configured as `django.contrib.gis.db.backends.postgis`.

## Local Setup

1. Create and activate a virtual environment.

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

2. Install dependencies.

```powershell
pip install -r requirements.txt
```

3. Apply migrations.

```powershell
python manage.py migrate
```

4. (Optional) Create a superuser.

```powershell
python manage.py createsuperuser
```

5. (Optional) Seed test data (zones, sensors, queue).

```powershell
python manage.py setup_test_data
```

6. Run the development server.

```powershell
python manage.py runserver
```

## Useful Management Commands

- Seed test dataset:

```powershell
python manage.py setup_test_data
```

- Reset queue notification sequence counters:

```powershell
python manage.py reset_sequence_numbers
```

## Main Routes

- `/` info/landing flow
- `/queueing/` chauffeur flow
- `/control/` officer login + dashboard
- `/admin/` Django admin
- `/api/v1/sensor-data/` sensor ingestion endpoint

## Sensor Ingestion API

Endpoint:

- `POST /api/v1/sensor-data/`

Authentication options:

- Basic auth with `label:raw_key`
- Or custom headers:
	- `Authorization: <raw_key>`
	- `label: <label>`

Expected request body includes:

- `sensor_info.serial_number`
- `status` (mapped to free/occupied)
- `timestamp` (optional, falls back to server time)

## Testing

Run tests with either Django test runner or pytest:

```powershell
python manage.py test
```

```powershell
pytest
```

## Notes for Development

- Current settings are development-friendly (`DEBUG=True`, broad host allowance).
- Harden security-related settings before production deployment.
- If geospatial dependencies are missing on your machine, install PostGIS-related runtime requirements before migrating.

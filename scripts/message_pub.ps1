# Tiny script that continually sends messages for testing.
# This script assumes the nats-cli is installed, and that a proper context has been setup prior to running.
$count = 1
while (1) {     
    nats pub nats.ui.demo "test message $count @ {{.TimeStamp}}"; 
    $count++
    Start-Sleep -Seconds 2
}

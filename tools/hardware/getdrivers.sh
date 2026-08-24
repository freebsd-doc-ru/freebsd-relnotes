find ~/freebsd-src/sys -name '*.c' -exec grep -H -A1 static driver_t '{}' \; to tools/hardware/15.1R_drivers.txt
grep -v "driver_t" tools/hardware/15.1R_drivers.txt to tools/hardware/15.1R_drivers_list.txt
perl tools/hardware/bin/hardware_report3.pl tools/hardware/15.1R_drivers_list.txt >delme3.txt
perl tools/hardware/bin/hardware_report2.pl tools/hardware/15.1R_drivers_list.txt >delme2.txt
perl tools/hardware/bin/hardware_report4.pl tools/hardware/15.1R_drivers_list.txt >delme4.txt
perl tools/hardware/bin/hardware_report5.pl tools/hardware/15.1R_drivers_list.txt tools/hardware/15.1R_drivers_modules.txt tools/hardware/15.1R_drivers_wifi.txt  >delme5.txt

find ~/freebsd-src/sys -name '*.c' -exec grep -H -E 'ATA_DECLARE_DRIVER\(|DRIVER_MODULE\(' '{}' \; >> tools/hardware/15.1R_drivers_modules.txt
^(.*.c):.+\(([^,]+)(,|\)).*
$1\t"$2"

static const struct ieee80211_ops

find ~/freebsd-src/sys -name '*.c' -exec grep -H -E 'ieee80211_alloc_hw\(' '{}' \; >> tools/hardware/15.1R_drivers_wifi.txt
find ~/freebsd-src/sys -name 'Makefile' -exec grep -H -E 'MT76_DRIVER_NAME\=' '{}' \; >> tools/hardware/15.1R_drivers_wifi2.txt
ieee80211_alloc_hw(
    MT76_DRIVER_NAME=

cat delme5.txt| awk '{if(substr($0,50,3)=="yes" && substr($0,56,3)=="yes" && substr($0,65,3)!="yes" ){print $0;}}' | wc

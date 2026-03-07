#!/usr/bin/env perl
use strict;
use warnings;
use File::Find;

my $base = "sys/dev";
my $man4dir = "share/man/man4";

my $hardware_file = "../freebsd-relnotes/releases/14.4R/hardware.adoc";

# Take list of drivers from hardware.adoc
my %hardware;
if (-f $hardware_file) {
    open(my $hf, "<", $hardware_file) or die "Cannot open $hardware_file: $!";
    while (my $line = <$hf>) {
        if ($line =~ /^\&hwlist\.(.+?);/) {
            my $name = $1;
            $hardware{$name} = 1;
        }
    }
    close($hf);
}

# Соберем список man4 файлов
my %man4;
my %man4_hardware_section;

if (-d $man4dir) {
    find(
        {
            wanted => sub {
                my ($foundfile) = $_;
                return unless -f $foundfile;
                return unless /\.4$/;

                my ($name) = $foundfile =~ /^(.+)\.4$/;
                return unless $name;

                my $nameman4 = $name;
                $nameman4 = ($nameman4 =~ s#^\Q$man4dir\E/?##r); # delete path to $man4dir
                $man4{$nameman4} = 1;

                # Проверка наличия секции HARDWARE
                #open(my $mf, "<", $File::Find::name) or return;
                #print "Before open with $foundfile\n";
                open(my $mf, "<", $foundfile) or return;
                #print "After open with $foundfile\n";
                while (my $line = <$mf>) {
                    if ($line =~ /^\.Sh\s+HARDWARE\b/ ||
                        $line =~ /^\.SH\s+HARDWARE\b/) {
                        $man4_hardware_section{$nameman4} = 1;
                        last;
                    }
                }
                close($mf);
            },
            no_chdir => 1
        },
        $man4dir
    );
}

# print join("\t",
#     "Driver",
#     "DRIVER_MODULE",
#     "probe/attach",
#     "ID_table",
#     "man4",
#     "HARDWARE_section",
#     "hardware.adoc",
#     "bus_types"
# ), "\n";

print join("\t",
    "Driver            ",
    "DRIVER_",
    "probe/",
    "ID_",
    "man4",
    "HARDWA-",
    "hardwa-",
    "bus_types"
), "\n";

print join("\t",
    "                  ",
    "MODULE",
    "attach",
    "table",
    "    ",
    "RE_sect",
    "re.adoc",
    ""
), "\n";


opendir(my $dh, $base) or die "Cannot open $base: $!";
my @dirs = sort grep { -d "$base/$_" && !/^\./ } readdir($dh);
closedir($dh);

foreach my $dir (@dirs) {

    my $path = "$base/$dir";

    my $has_driver_module = 0;
    my $has_probe_attach  = 0;
    my $has_id_table      = 0;
    my %bus_types;

    find(
        {
            wanted => sub {
                return unless -f $_;
                return unless /\.(c|h)$/;

                open(my $fh, "<", $_) or return;
                while (my $line = <$fh>) {

                    $has_driver_module = 1 if $line =~ /\bDRIVER_MODULE\s*\(/;

                    if ($line =~ /\bprobe\s*\(/) {
                        $has_probe_attach = 1;
                    }
                    if ($line =~ /\battach\s*\(/) {
                        $has_probe_attach = 1;
                    }

                    # PCI ID table
                    if ($line =~ /\bPCI_DEVICE\b/ ||
                        $line =~ /pci_device_id/ ||
                        $line =~ /struct\s+pci_device_id/) {
                        $has_id_table = 1;
                        $bus_types{pci} = 1;
                    }

                    # USB ID table
                    if ($line =~ /\bUSB_VPI\b/ ||
                        $line =~ /usb_device_id/ ||
                        $line =~ /struct\s+usb_device_id/) {
                        $has_id_table = 1;
                        $bus_types{usb} = 1;
                    }

                    # ACPI
                    if ($line =~ /acpi_/i) {
                        $bus_types{acpi} = 1;
                    }

                    # ISA
                    if ($line =~ /\bisa_/i) {
                        $bus_types{isa} = 1;
                    }

                    # I2C / IIC
                    if ($line =~ /\biic_/i) {
                        $bus_types{iic} = 1;
                    }

                    # OFW / FDT
                    if ($line =~ /ofw_|fdt_/i) {
                        $bus_types{ofw} = 1;
                    }

                    # MMC
                    if ($line =~ /\bmmc_/i) {
                        $bus_types{mmc} = 1;
                    }

                    # SPI
                    if ($line =~ /\bspi_|spibus_/i) {
                        $bus_types{spi} = 1;
                    }

                    # PCI/USB driver framework style (как ты упоминал)
                    if ($line =~ /\bpci_driver\b/) {
                        $bus_types{pci} = 1;
                    }
                    if ($line =~ /\busb_driver\b/) {
                        $bus_types{usb} = 1;
                    }
                }
                close($fh);
            },
            no_chdir => 1
        },
        $path
    );

    # man4 проверка
    my $has_man4 = $man4{$dir} ? 1 : 0;
    my $has_hw_section = $man4_hardware_section{$dir} ? 1 : 0;
    # выводим если есть хоть один из критериев 1–4
    if ($has_driver_module || $has_probe_attach || $has_id_table || $has_man4) {

        my $bus_string = join(",", sort keys %bus_types);
        my $in_hardware = $hardware{$dir} ? 1 : 0;
        print join("\t",
            substr($dir." "x20,0,20),
            $has_driver_module ? "yes" : "   ",
            $has_probe_attach  ? "yes" : "   ",
            $has_id_table      ? "yes" : "   ",
            $has_man4          ? "yes" : "   ",
            $has_hw_section    ? "yes" : "   ",
            $in_hardware       ? "yes" : "   ",
            $bus_string
        ), "\n";
        delete $hardware{$dir};
        delete $man4{$dir};
    }
}

foreach my $drv (sort keys %hardware) {
    my $has_man4 = $man4{$drv} ? 1 : 0;
    my $has_hw_section = $man4_hardware_section{$drv} ? 1 : 0;
    print join("\t",
        substr($drv." "x20,0,20),
        "NO ",   # DRIVER_MODULE
        "DRV",   # probe/attach
        "   ",   # ID_table
        $has_man4          ? "yes" : "   ",,   # man4
        $has_hw_section    ? "yes" : "   ",
        "yes",   # hardware.adoc
        ""       # bus_types
    ), "\n";
    delete $man4{$drv};
}

foreach my $drv (sort keys %man4) {
    my $has_man4 = $man4{$drv} ? 1 : 0;
    my $has_hw_section = $man4_hardware_section{$drv} ? 1 : 0;
    print join("\t",
        substr($drv." "x20,0,20),
        "NO ",   # DRIVER_MODULE
        "DRV",   # probe/attach
        "   ",   # ID_table
        $has_man4          ? "yes" : "   ",,   # man4
        "   ",   # hardware.adoc
        ""       # bus_types
    ), "\n";
    delete $man4{$drv};
}

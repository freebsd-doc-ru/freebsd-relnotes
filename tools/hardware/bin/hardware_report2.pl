#!/usr/bin/env perl
use strict;
use warnings;

my $man4dir = "../freebsd-src/share/man/man4";
my $hardware_file = "../freebsd-doc/website/archetypes/release/hardware.adoc";

# Проверка аргумента командной строки
my $list_file = $ARGV[0];
die "Usage: $0 <file_with_driver_list>\n" unless $list_file;

# --- Чтение hardware.adoc ---
my %hardware;
if (-f $hardware_file) {
    open(my $hf, "<", $hardware_file) or die "Cannot open $hardware_file: $!";
    while (my $line = <$hf>) {
        if ($line =~ /^\&hwlist\.(.+?);/) {
            $hardware{$1} = 1;
        }
    }
    close($hf);
}

# --- Чтение списка драйверов из файла ---
my @drivers;
open(my $lf, "<", $list_file) or die "Cannot open $list_file: $!";
while (my $line = <$lf>) {
    chomp $line;
    next if $line =~ /^\s*$/;          # пустые строки
    next if $line =~ /^\s*#/;          # комментарии

    my ($file_path, $driver_quoted) = split /\t/, $line, 2;
    unless (defined $driver_quoted) {
        warn "Skipping malformed line (no tab): $line\n";
        next;
    }

    # Убираем кавычки у имени драйвера
    $driver_quoted =~ s/^"|"$//g;
    my $driver_name = $driver_quoted;

    # Обработка ~ в пути файла
    $file_path =~ s/^~/$ENV{HOME}/ if defined $ENV{HOME};

    push @drivers, { file => $file_path, name => $driver_name };
}
close($lf);

# --- Функция проверки man-страницы и секции HARDWARE ---
sub check_man4 {
    my ($driver) = @_;
    my $man4_file = "$man4dir/$driver.4";
    my ($has_man4, $has_hw_section) = (0, 0);

    if (-f $man4_file) {
        $has_man4 = 1;
        open(my $mf, "<", $man4_file) or return ($has_man4, $has_hw_section);
        while (my $line = <$mf>) {
            if ($line =~ /^\.Sh\s+HARDWARE\b/ || $line =~ /^\.SH\s+HARDWARE\b/) {
                $has_hw_section = 1;
                last;
            }
        }
        close($mf);
    }
    return ($has_man4, $has_hw_section);
}

# --- Вывод заголовка ---
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
    "tbl",
    "    ",
    "RE_sect",
    "re.adoc",
    ""
), "\n";

# --- Обработка каждого драйвера из списка ---
foreach my $drv (@drivers) {
    my $file = $drv->{file};
    my $name = $drv->{name};

    unless (-f $file) {
        warn "File not found: $file (driver $name)\n";
        next;
    }

    # Анализ исходного файла
    my ($has_driver_module, $has_probe_attach, $has_id_table) = (0, 0, 0);
    my %bus_types;

    open(my $fh, "<", $file) or do {
        warn "Cannot open $file: $!";
        next;
    };
    while (my $line = <$fh>) {
        $has_driver_module = 1 if $line =~ /\bDRIVER_MODULE\s*\(/;

        if ($line =~ /\bprobe\s*\(/ || $line =~ /\battach\s*\(/) {
            $has_probe_attach = 1;
        }

        # PCI ID table
        if ($line =~ /\bPCI_DEVICE\b/ || $line =~ /pci_device_id/ || $line =~ /struct\s+pci_device_id/) {
            $has_id_table = 1;
            $bus_types{pci} = 1;
        }

        # USB ID table
        if ($line =~ /\bUSB_VPI\b/ || $line =~ /usb_device_id/ || $line =~ /struct\s+usb_device_id/) {
            $has_id_table = 1;
            $bus_types{usb} = 1;
        }

        # ACPI, ISA, I2C, OFW, MMC, SPI и т.д.
        $bus_types{acpi} = 1 if $line =~ /acpi_/i;
        $bus_types{isa}  = 1 if $line =~ /\bisa_/i;
        $bus_types{iic}  = 1 if $line =~ /\biic_/i;
        $bus_types{ofw}  = 1 if $line =~ /ofw_|fdt_/i;
        $bus_types{mmc}  = 1 if $line =~ /\bmmc_/i;
        $bus_types{spi}  = 1 if $line =~ /\bspi_|spibus_/i;

        # Специфичные драйверные фреймворки
        $bus_types{pci} = 1 if $line =~ /\bpci_driver\b/;
        $bus_types{usb} = 1 if $line =~ /\busb_driver\b/;
    }
    close($fh);

    # Проверка man-страницы
    my ($has_man4, $has_hw_section) = check_man4($name);
    my $in_hardware = exists $hardware{$name} ? 1 : 0;

    # Формирование строки вывода
    my $bus_string = join(",", sort keys %bus_types);
    print join("\t",
        substr($name . " " x 20, 0, 20),
        $has_driver_module ? "yes" : " - ",
        $has_probe_attach  ? "yes   " : " -    ",
        $has_id_table      ? "yes" : " - ",
        $has_man4          ? "yes " : " -  ",
        $has_hw_section    ? "yes    " : " -     ",
        $in_hardware       ? "yes    " : " -     ",
        $bus_string
    ), "\n";
}

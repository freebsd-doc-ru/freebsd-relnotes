#!/usr/bin/env perl
use strict;
use warnings;
use File::Find;

my $man4dir = "../freebsd-src/share/man/man4";
my $hardware_file = "../freebsd-doc/website/archetypes/release/hardware.adoc";

# --- Проверка аргумента командной строки ---
my $list_file = $ARGV[0];
die "Usage: $0 <file_with_driver_list>\n" unless $list_file;

# --- Чтение hardware.adoc (список драйверов из документации) ---
my %hardware_full;                     # полное имя (с возможным подкаталогом) -> 1
my %hardware_basename_to_full;         # базовое имя -> полное имя

if (-f $hardware_file) {
    open(my $hf, "<", $hardware_file) or die "Cannot open $hardware_file: $!";
    while (my $line = <$hf>) {
        if ($line =~ /^\&hwlist\.(.+?);/) {
            my $fullname = $1;
            $hardware_full{$fullname} = 1;
            # извлекаем базовое имя (после последнего '/')
            my $basename = $fullname;
            $basename =~ s/.*\///;
            $hardware_basename_to_full{$basename} = $fullname;
        }
    }
    close($hf);
}

# --- Сканирование man-страниц (наличие файла .4 и секции HARDWARE) ---
my %man4;                   # относительный путь (с возможными подкаталогами) -> 1
my %man4_hardware_section;  # относительный путь -> наличие секции HARDWARE

if (-d $man4dir) {
    find({
        wanted => sub {
            return unless -f $_;
            return unless /\.4$/;
            my ($name) = $_ =~ /^(.+)\.4$/;
            return unless $name;
            my $relname = $name;
            $relname =~ s#^\Q$man4dir\E/?##;
            $man4{$relname} = 1;

            open(my $mf, "<", $File::Find::name) or return;
            while (my $line = <$mf>) {
                if ($line =~ /^\.Sh\s+HARDWARE\b/ || $line =~ /^\.SH\s+HARDWARE\b/) {
                    $man4_hardware_section{$relname} = 1;
                    last;
                }
            }
            close($mf);
        },
        no_chdir => 1
    }, $man4dir);
}

# --- Чтение списка драйверов из файла (замена скана sys/dev) ---
my @driver_list;   # элементы: { name => $базовое_имя, file => $путь }
open(my $lf, "<", $list_file) or die "Cannot open $list_file: $!";
while (my $line = <$lf>) {
    chomp $line;
    next if $line =~ /^\s*$/;
    next if $line =~ /^\s*#/;

    my ($file_path, $driver_quoted) = split /\t/, $line, 2;
    unless (defined $driver_quoted) {
        warn "Skipping malformed line (no tab): $line\n";
        next;
    }
    $driver_quoted =~ s/^"|"$//g;
    my $driver_name = $driver_quoted;
    $file_path =~ s/^~/$ENV{HOME}/ if defined $ENV{HOME};

    push @driver_list, { name => $driver_name, file => $file_path };
}
close($lf);

# --- Вспомогательная функция анализа исходного файла ---
sub analyze_source_file {
    my ($file) = @_;
    my ($has_driver_module, $has_probe_attach, $has_id_table) = (0, 0, 0);
    my %bus_types;

    open(my $fh, "<", $file) or return (0, 0, 0, "");
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
        # Другие шины
        $bus_types{acpi} = 1 if $line =~ /acpi_/i;
        $bus_types{isa}  = 1 if $line =~ /\bisa_/i;
        $bus_types{iic}  = 1 if $line =~ /\biic_/i;
        $bus_types{ofw}  = 1 if $line =~ /ofw_|fdt_/i;
        $bus_types{mmc}  = 1 if $line =~ /\bmmc_/i;
        $bus_types{spi}  = 1 if $line =~ /\bspi_|spibus_/i;
        $bus_types{pci}  = 1 if $line =~ /\bpci_driver\b/;
        $bus_types{usb}  = 1 if $line =~ /\busb_driver\b/;
    }
    close($fh);
    my $bus_string = join(",", sort keys %bus_types);
    return ($has_driver_module, $has_probe_attach, $has_id_table, $bus_string);
}

# --- Вывод заголовка (фиксированная ширина для форматирования) ---
printf "%-20s %-8s %-8s %-4s %-5s %-8s %-8s %-20s %s\n",
    "Driver", "DRIVER_", "probe/", "ID_", "man4", "HARDWA-", "hardwa-", "bus_types", "source_file";
printf "%-20s %-8s %-8s %-4s %-5s %-8s %-8s %-20s %s\n",
    "", "MODULE", "attach", "tbl", "", "RE_sect", "re.adoc", "", "";

# --- 1. Драйверы из списка (замена обхода sys/dev) ---
foreach my $drv (@driver_list) {
    my $name = $drv->{name};
    my $file = $drv->{file};

    my ($has_driver_module, $has_probe_attach, $has_id_table, $bus_string);
    if (-f $file) {
        ($has_driver_module, $has_probe_attach, $has_id_table, $bus_string) = analyze_source_file($file);
    } else {
        warn "File not found: $file (driver $name)\n";
        ($has_driver_module, $has_probe_attach, $has_id_table, $bus_string) = (0, 0, 0, "");
    }
    $has_driver_module = 1; # it always true (taken from the list)

    # Проверка man-страницы по базовому имени (как было в оригинале)
    my $has_man4          = $man4{$name}          ? 1 : 0;
    my $has_hw_section    = $man4_hardware_section{$name} ? 1 : 0;

    # Присутствие в hardware.adoc – по базовому имени
    my $in_hardware = exists $hardware_basename_to_full{$name} ? 1 : 0;

    # Если драйвер есть в hardware.adoc – удаляем его полное имя, чтобы не выводить повторно
    if ($in_hardware) {
        my $full = $hardware_basename_to_full{$name};
        delete $hardware_full{$full};
        delete $hardware_basename_to_full{$name};
    }

    # Удаляем из man4, чтобы не дублировать в третьем цикле
    delete $man4{$name};

    printf "%-20s %-8s %-8s %-4s %-5s %-8s %-8s %-20s %s\n",
        substr($name . " " x 20, 0, 20),
        $has_driver_module ? "yes" : "-",
        $has_probe_attach  ? "yes" : "-",
        $has_id_table      ? "yes" : "-",
        $has_man4          ? "yes" : "-",
        $has_hw_section    ? "yes" : "-",
        $in_hardware       ? "yes" : "-",
        $bus_string,
        $file;
}

# --- 2. Драйверы, которые остались только в hardware.adoc ---
foreach my $fullname (sort keys %hardware_full) {
    # Для поиска man-страницы используем ПОЛНОЕ имя (с подкаталогом)
    my $has_man4          = $man4{$fullname}          ? 1 : 0;
    my $has_hw_section    = $man4_hardware_section{$fullname} ? 1 : 0;

    # Удаляем из man4, чтобы не выводить в третьем цикле
    delete $man4{$fullname};

    printf "%-20s %-8s %-8s %-4s %-5s %-8s %-8s %-20s %s\n",
        substr($fullname . " " x 20, 0, 20),
        "NO", "DRV", "-",
        $has_man4          ? "yes" : "-",
        $has_hw_section    ? "yes" : "-",
        "yes",
        "",
        "-";
}

# --- 3. Драйверы, которые есть только в man-страницах ---
foreach my $man (sort keys %man4) {
    my $has_hw_section = $man4_hardware_section{$man} ? 1 : 0;

    printf "%-20s %-8s %-8s %-4s %-5s %-8s %-8s %-20s %s\n",
        substr($man . " " x 20, 0, 20),
        "NO", "DRV", "-",
        "yes",                       # man-файл заведомо существует
        $has_hw_section ? "yes" : "-",
        "-",
        "",
        "-";
}

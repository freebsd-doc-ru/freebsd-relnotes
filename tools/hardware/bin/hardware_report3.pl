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

# --- Сканирование man-страниц (наличие файла .4 и секции HARDWARE) ---
my %man4;
my %man4_hardware_section;

if (-d $man4dir) {
    find({
        wanted => sub {
            return unless -f $_;
            return unless /\.4$/;
            my ($name) = $_ =~ /^(.+)\.4$/;
            return unless $name;
            my $nameman4 = $name;
            $nameman4 =~ s#^\Q$man4dir\E/?##;
            $man4{$nameman4} = 1;

            open(my $mf, "<", $File::Find::name) or return;
            while (my $line = <$mf>) {
                if ($line =~ /^\.Sh\s+HARDWARE\b/ || $line =~ /^\.SH\s+HARDWARE\b/) {
                    $man4_hardware_section{$nameman4} = 1;
                    last;
                }
            }
            close($mf);
        },
        no_chdir => 1
    }, $man4dir);
}

# --- Чтение списка драйверов из файла (замена скана sys/dev) ---
my @driver_list;   # элементы: { name => $имя, file => $путь }
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

    # Убираем кавычки у имени драйвера
    $driver_quoted =~ s/^"|"$//g;
    my $driver_name = $driver_quoted;

    # Заменяем ~ на домашний каталог
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

# --- Вывод заголовка (ширины столбцов заданы для ровного форматирования) ---
printf "%-20s %-8s %-8s %-4s %-5s %-8s %-8s %-20s %s\n",
    "Driver", "DRIVER_", "probe/", "ID_", "man4", "HARDWA-", "hardwa-", "bus_types", "source_file";
printf "%-20s %-8s %-8s %-4s %-5s %-8s %-8s %-20s %s\n",
    "", "MODULE", "attach", "tbl", "", "RE_sect", "re.adoc", "", "";

# --- 1. Обработка драйверов из списка (замена sys/dev) ---
foreach my $drv (@driver_list) {
    my $name = $drv->{name};
    my $file = $drv->{file};

    # Анализ исходного файла (только если он существует)
    my ($has_driver_module, $has_probe_attach, $has_id_table, $bus_string);
    if (-f $file) {
        ($has_driver_module, $has_probe_attach, $has_id_table, $bus_string) = analyze_source_file($file);
    } else {
        warn "File not found: $file (driver $name)\n";
        ($has_driver_module, $has_probe_attach, $has_id_table, $bus_string) = (0, 0, 0, "");
    }

    my $has_man4          = $man4{$name}          ? 1 : 0;
    my $has_hw_section    = $man4_hardware_section{$name} ? 1 : 0;
    my $in_hardware       = $hardware{$name}      ? 1 : 0;

    # Удаляем из оставшихся хэшей, чтобы они не попали в следующие циклы
    delete $hardware{$name};
    delete $man4{$name};

    # Форматированный вывод с шириной 20 для bus_types
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

# --- 2. Драйверы, которые есть только в hardware.adoc ---
foreach my $drv (sort keys %hardware) {
    my $has_man4          = $man4{$drv}          ? 1 : 0;
    my $has_hw_section    = $man4_hardware_section{$drv} ? 1 : 0;

    delete $man4{$drv};   # чтобы не дублировать

    printf "%-20s %-8s %-8s %-4s %-5s %-8s %-8s %-20s %s\n",
        substr($drv . " " x 20, 0, 20),
        "NO", "DRV", "-",
        $has_man4          ? "yes" : "-",
        $has_hw_section    ? "yes" : "-",
        "yes",
        "",
        "-";
}

# --- 3. Драйверы, которые есть только в man-страницах ---
foreach my $drv (sort keys %man4) {
    my $has_man4          = $man4{$drv}          ? 1 : 0;
    my $has_hw_section    = $man4_hardware_section{$drv} ? 1 : 0;

    printf "%-20s %-8s %-8s %-4s %-5s %-8s %-8s %-20s %s\n",
        substr($drv . " " x 20, 0, 20),
        "NO", "DRV", "-",
        $has_man4          ? "yes" : "-",
        $has_hw_section    ? "yes" : "-",
        "-",
        "",
        "-";
}

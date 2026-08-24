#!/usr/bin/env perl
use strict;
use warnings;
use File::Find;
use File::Basename qw(basename);
use Cwd qw(abs_path);

# --- Проверка аргументов командной строки ---
my $freebsd_src = $ARGV[0];
my $input_table = $ARGV[1];
my $output_file = $ARGV[2] // "drivers_with_versions.txt";

die "Usage: $0 <freebsd-src-dir> <input-table-file> [output-file]\n"
    unless $freebsd_src && $input_table;

# --- Проверка существования каталога FreeBSD ---
die "FreeBSD source directory not found: $freebsd_src\n" unless -d $freebsd_src;

# --- Функция извлечения номера версии из файла newvers.sh в конкретном коммите ---
sub get_freebsd_version {
    my ($git_dir, $commit_hash) = @_;
    return "unknown" if $commit_hash eq "none" || $commit_hash eq "missing";

    my $newvers_content = `git --git-dir=$git_dir/.git show $commit_hash:sys/conf/newvers.sh 2>/dev/null`;

    return "unknown" unless $? == 0 && $newvers_content;

    if ($newvers_content =~ /^REVISION="([^"]+)"/m) {
        #print "git_dir $git_dir, commit_hash $commit_hash newvers_content $1\n";
        return $1;
    }
    return "unknown";
}

# --- Функция получения первого и последнего хешей файла ---
sub get_file_hashes {
    my ($git_dir, $file_path) = @_;

    my $first_hash = `git --git-dir=$git_dir/.git log --reverse --format=%H -- "$file_path" 2>/dev/null | head -1`;
    chomp $first_hash;
    $first_hash = "none" unless $first_hash && $? == 0;

    my $last_hash = `git --git-dir=$git_dir/.git log -1 --format=%H -- "$file_path" 2>/dev/null`;
    chomp $last_hash;
    $last_hash = "none" unless $last_hash && $? == 0;

    return ($first_hash, $last_hash);
}

# --- Функция поиска man-файла .4 по имени драйвера ---
sub find_man4_file {
    my ($driver_name, $man4_dir) = @_;

    # Ищем файл $driver_name.4 (возможно, в подкаталогах)
    my $found_path = "";
    find({
        wanted => sub {
            return unless -f $_;
            return unless /\.4$/;
            my ($name) = $_ =~ /^(.+)\.4$/;
            return unless $name;
            my $base = basename($name);
            # Убираем расширение (если есть, но обычно .4)
            $base =~ s/\.[^.]*$// if $base =~ /\./ && $base !~ /^\./;
            if ($base eq $driver_name) {
                # Нашли: относительный путь от man4dir
                my $rel = $_;
                $rel =~ s#^\Q$man4_dir\E/?##;
                $found_path = $rel ; #. ".4";
                return;
            }
        },
        no_chdir => 1
    }, $man4_dir);
    print "found_path $found_path\n";
    return 'share/man/man4/'.$found_path if $found_path;
    return "";
}

# --- Функция для получения версий для файла (общая для source и man) ---
sub get_file_versions {
    my ($git_dir, $file_path) = @_;
    my ($min_ver, $max_ver) = ("missing", "missing");

    if ($file_path && -f "$git_dir/$file_path") {
        my ($first_hash, $last_hash) = get_file_hashes($git_dir, $file_path);
        $min_ver = get_freebsd_version($git_dir, $first_hash);
        $max_ver = get_freebsd_version($git_dir, $last_hash);
    }
    return ($min_ver, $max_ver);
}

# --- Определение колонки source_file (ищем слово "source_file" в заголовке) ---
sub find_source_file_column {
    my ($header_lines_ref) = @_;
    foreach my $line (@$header_lines_ref) {
        if ($line =~ /\bsource_file\b/) {
            return index($line, "source_file");
        }
    }
    return -1;
}

# --- Чтение входного файла ---
open(my $in_fh, "<", $input_table) or die "Cannot open $input_table: $!";
open(my $out_fh, ">", $output_file) or die "Cannot create $output_file: $!";

# --- Сбор заголовочных строк и определение позиции source_file ---
my @header_lines = ();
my $source_col_pos = -1;

while (my $line = <$in_fh>) {
    last if $line =~ /^-/;  # до строки разделителя
    next if $line =~ /^\s*$/;
    push @header_lines, $line;
}

# Определяем позицию колонки source_file по сохранённым заголовкам
$source_col_pos = find_source_file_column(\@header_lines);

# --- Вывод новых заголовков (с добавленными столбцами Min man, Max man) ---
# Первая строка заголовка обычно содержит имена колонок
my $first_header = $header_lines[0];
$first_header =~ s/^\s+//;  # убираем ведущие пробелы
# Вставляем два новых столбца в начало
print $out_fh "Min man Max man $first_header";
# Вторая строка (подзаголовки) - подгоняем
if ($header_lines[1]) {
    my $second_header = $header_lines[1];
    $second_header =~ s/^\s+//;
    # Добавляем пустые подзаголовки для новых колонок (по 8 символов каждый)
    print $out_fh "                $second_header";
}
print $out_fh "-" x 80 . "\n";

# --- Возвращаемся к началу файла для обработки данных ---
seek($in_fh, 0, 0);

# Пропускаем заголовки в основном проходе
my $in_data = 0;
my $git_dir = abs_path($freebsd_src);
my $man4_dir = "$freebsd_src/share/man/man4";

while (my $line = <$in_fh>) {
    # Пропускаем заголовки и разделители
    next if $line =~ /^Driver/ || $line =~ /^\s*$/ || $line =~ /^-/;
    next if $line =~ /MODULE/;  # строка с подзаголовками

    $in_data = 1;

    # --- Извлечение имени драйвера (первый столбец) ---
    my $driver_name = "";
    if ($line =~ /^(\S+)/) {
        $driver_name = $1;
    } else {
        warn "Cannot extract driver name from line: $line\n";
        print $out_fh "missing missing unknown unknown $line";
        next;
    }

    # --- Поиск man-файла и получение его версий ---
    my ($min_man, $max_man) = ("missing", "missing");
    if (-d $man4_dir) {
        my $man_file = find_man4_file($driver_name, $man4_dir);
        if ($man_file) {
            ($min_man, $max_man) = get_file_versions($git_dir, $man_file);
        } else {
            # Попробуем просто $driver_name.4 без подкаталога
            my $simple_man = "share/man/man4/$driver_name.4";
            if (-f "$freebsd_src/$simple_man") {
                ($min_man, $max_man) = get_file_versions($git_dir, $simple_man);
            }
            else
            {
                print "Not found $simple_man\n"
            }
        }
    }
    else
    {
        print "No man dir\n";
    }

    # --- Извлечение source_file и его версий ---
    my $source_file = "";
    my ($min_src, $max_src) = ("missing", "missing");

    if ($source_col_pos >= 0 && length($line) > $source_col_pos) {
        my $rest = substr($line, $source_col_pos);
        $rest =~ s/^\s+//;
        $source_file = $rest;
        $source_file =~ s/\s.*$//;
    } else {
        # Fallback: последнее слово
        my @fields = split(/\s+/, $line);
        $source_file = $fields[-1];
    }

    if ($source_file && -f "$freebsd_src/$source_file") {
        ($min_src, $max_src) = get_file_versions($git_dir, $source_file);
    } else {
        warn "Source file not found: $source_file\n";
    }

    # --- Вывод строки с добавленными столбцами в начале ---
    printf $out_fh "%-8s %-8s %-8s %-8s %s",
        $min_man, $max_man, $min_src, $max_src, $line;
}

close($in_fh);
close($out_fh);

print "Done. Output written to: $output_file\n";

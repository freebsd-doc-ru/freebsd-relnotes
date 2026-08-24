#!/usr/bin/env perl
use strict;
use warnings;
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

    # Команда: git --git-dir=REPO/.git show ХЕШ:sys/conf/newvers.sh
    my $newvers_content = `git --git-dir=$git_dir/.git show $commit_hash:sys/conf/newvers.sh 2>/dev/null`;
    return "unknown" unless $? == 0 && $newvers_content;

    # Ищем строку REVISION="X.Y"
    if ($newvers_content =~ /^REVISION="([^"]+)"/m) {
        return $1;
    }

    return "unknown";
}

# --- Функция получения первого и последнего хешей файла ---
sub get_file_hashes {
    my ($git_dir, $file_path) = @_;

    # Первый коммит (когда файл появился)
    my $first_hash = `git --git-dir=$git_dir/.git log --reverse --format=%H -- "$file_path" 2>/dev/null | head -1`;
    chomp $first_hash;
    $first_hash = "none" unless $first_hash && $? == 0;

    # Последний коммит (последнее изменение)
    my $last_hash = `git --git-dir=$git_dir/.git log -1 --format=%H -- "$file_path" 2>/dev/null`;
    chomp $last_hash;
    $last_hash = "none" unless $last_hash && $? == 0;

    return ($first_hash, $last_hash);
}

# --- Определение позиции колонки source_file по заголовку ---
sub find_source_file_column {
    my ($header_line) = @_;

    # Заголовок имеет вид: "... bus_types         source_file"
    # Ищем последнее слово в строке
    if ($header_line =~ /(\S+)\s*$/) {
        my $last_word = $1;
        if ($last_word eq "source_file") {
            # Находим позицию начала этого слова
            my $pos = index($header_line, "source_file");
            return $pos if $pos >= 0;
        }
    }

    # Fallback: ищем по шаблону с пробелами
    if ($header_line =~ /(bus_types\s+source_file)/) {
        my $pos = index($header_line, "source_file");
        return $pos if $pos >= 0;
    }

    # Если не нашли, возвращаем позицию последнего слова
    my @words = split(/\s+/, $header_line);
    my $last_word = $words[-1];
    return rindex($header_line, $last_word);
}

# --- Чтение входного файла ---
open(my $in_fh, "<", $input_table) or die "Cannot open $input_table: $!";
open(my $out_fh, ">", $output_file) or die "Cannot create $output_file: $!";

# --- Обработка заголовков ---
my @header_lines = ();
my $source_col_pos = -1;

while (my $line = <$in_fh>) {
    # Пропускаем пустые строки
    next if $line =~ /^\s*$/;

    # Сохраняем заголовочные строки
    if ($line =~ /^Driver/ || $line =~ /^\s*$/ || $line =~ /^                   MODULE/) {
        push @header_lines, $line;

        # Если это первая строка заголовка, определяем позицию source_file
        if ($line =~ /^Driver/ && $source_col_pos == -1) {
            $source_col_pos = find_source_file_column($line);
        }
        print "$source_col_pos $line\n";
        next;
    }

    # Как только дошли до строки с разделителем, выходим из сбора заголовков
    last if $line =~ /^-/;
}

# --- Вывод новых заголовков ---
print $out_fh "Min     Max     " . $header_lines[0];
print $out_fh $header_lines[1] if $header_lines[1];
print $out_fh $header_lines[2] if $header_lines[2];
print $out_fh "-" x 80 . "\n";

# --- Возвращаемся к началу файла для обработки данных ---
seek($in_fh, 0, 0);

# Пропускаем заголовки в основном проходе
my $in_data = 0;
my $git_dir = abs_path($freebsd_src);

while (my $line = <$in_fh>) {
    # Пропускаем заголовки
    next if $line =~ /^Driver/ || $line =~ /^\s*$/ || $line =~ /^-/ || $line =~ /^                   MODULE/;

    # Начинаем обработку данных
    $in_data = 1 if $line =~ /^\S/;
    last if !$in_data;
    print $line;
    # Извлекаем путь к source_file
    my $source_file = "";
    if ($source_col_pos >= 0 && length($line) > $source_col_pos) {
        my $rest = substr($line, $source_col_pos);
        $rest =~ s/^\s+//;
        $source_file = $rest;
        $source_file =~ s/\s.*$//;  # Берём первое слово (путь без пробелов)
    } else {
        # Fallback: последнее слово в строке
        my @fields = split(/\s+/, $line);
        $source_file = $fields[-1];
    }

    # Проверяем существование файла (относительно корня FreeBSD)
    my $full_path = "$freebsd_src/$source_file";
    if (!-f $full_path) {
        warn "File not found: $full_path\n";
        print $out_fh "unknown unknown $line";
        next;
    }

    # Получаем хеши
    my ($first_hash, $last_hash) = get_file_hashes($freebsd_src, $source_file);

    # Получаем версии FreeBSD для этих хешей
    my $min_version = "none";
    my $max_version = "none";

    if ($first_hash ne "none") {
        $min_version = get_freebsd_version($freebsd_src, $first_hash);
    }

    if ($last_hash ne "none") {
        $max_version = get_freebsd_version($freebsd_src, $last_hash);
    }

    # Форматируем версии (выравнивание по 8 символов)
    printf $out_fh "%-8s %-8s %s", $min_version, $max_version, $line;
}

close($in_fh);
close($out_fh);

print "Done. Output written to: $output_file\n";

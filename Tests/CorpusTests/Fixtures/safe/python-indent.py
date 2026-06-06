def repair(text, width=None):
    lines = text.splitlines()
    if not lines:
        return text
    for index, line in enumerate(lines):
        if should_rejoin(line, width):
            lines[index] = line.rstrip()
        else:
            continue
    return "\n".join(lines)

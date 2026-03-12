const TODO_LINE_REGEX = /^(\s*)((?:[-*+])|(?:\d+\.))(\s+\[)( |x|X)(\]\s*)(.*)$/;

export const PRIVATE_NOTE_TODO_TEMPLATE = '- [ ] Task';

export const parsePrivateNoteTodoLine = (line, lineIndex = -1) => {
  const match = line.match(TODO_LINE_REGEX);

  if (!match) {
    return null;
  }

  return {
    checked: match[4].toLowerCase() === 'x',
    label: match[6].trim(),
    lineIndex,
    raw: line,
  };
};

export const hasPrivateNoteTodos = content => {
  return (content || '')
    .split('\n')
    .some(line => parsePrivateNoteTodoLine(line));
};

export const parsePrivateNoteSections = content => {
  const lines = (content || '').split('\n');
  const sections = [];
  let textLines = [];
  let taskItems = [];

  const flushTextSection = () => {
    const textContent = textLines.join('\n').trim();

    if (textContent) {
      sections.push({
        type: 'text',
        content: textContent,
      });
    }

    textLines = [];
  };

  const flushTaskSection = () => {
    if (taskItems.length) {
      sections.push({
        type: 'tasks',
        items: [...taskItems],
      });
    }

    taskItems = [];
  };

  lines.forEach((line, lineIndex) => {
    const todoItem = parsePrivateNoteTodoLine(line, lineIndex);

    if (todoItem) {
      flushTextSection();
      taskItems.push(todoItem);
      return;
    }

    flushTaskSection();
    textLines.push(line);
  });

  flushTaskSection();
  flushTextSection();

  return sections;
};

export const getPrivateNoteTodoProgress = items => {
  const done = items.filter(item => item.checked).length;

  return {
    done,
    total: items.length,
  };
};

export const togglePrivateNoteTodo = (content, lineIndex) => {
  const lines = (content || '').split('\n');
  const line = lines[lineIndex];
  const match = line?.match(TODO_LINE_REGEX);

  if (!match) {
    return content || '';
  }

  const nextState = match[4].toLowerCase() === 'x' ? ' ' : 'x';
  lines[lineIndex] = [
    match[1],
    match[2],
    match[3],
    nextState,
    match[5],
    match[6],
  ].join('');

  return lines.join('\n');
};

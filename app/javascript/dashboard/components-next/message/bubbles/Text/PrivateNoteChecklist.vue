<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import FormattedContent from './FormattedContent.vue';

import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { useMessageContext } from '../../provider.js';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import {
  getPrivateNoteTodoProgress,
  parsePrivateNoteSections,
  togglePrivateNoteTodo,
} from 'dashboard/helper/privateNoteTodoHelper';

const props = defineProps({
  content: {
    type: String,
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();
const { conversationId, id: messageId } = useMessageContext();

const isUpdating = ref(false);
const savingLineIndex = ref(null);
const pendingStates = ref({});

const sections = computed(() => parsePrivateNoteSections(props.content));

watch(
  () => props.content,
  () => {
    pendingStates.value = {};
    isUpdating.value = false;
    savingLineIndex.value = null;
  }
);

const checkboxValue = item => {
  const pendingValue = pendingStates.value[item.lineIndex];
  return pendingValue === undefined ? item.checked : pendingValue;
};

const progressLabel = items => {
  const { done, total } = getPrivateNoteTodoProgress(items);

  return t('CONVERSATION.PRIVATE_NOTES.TODO.PROGRESS', {
    done,
    total,
  });
};

const formatTodoLabel = label => {
  return new MessageFormatter(label, false, true).formattedMessage
    .replace(/^<p>/, '')
    .replace(/<\/p>\s*$/, '');
};

const toggleTodo = async (item, checked) => {
  if (isUpdating.value) {
    return;
  }

  const updatedContent = togglePrivateNoteTodo(props.content, item.lineIndex);

  if (updatedContent === props.content) {
    return;
  }

  pendingStates.value = {
    ...pendingStates.value,
    [item.lineIndex]: checked,
  };
  isUpdating.value = true;
  savingLineIndex.value = item.lineIndex;

  try {
    await store.dispatch('updatePrivateNote', {
      conversationId: conversationId.value,
      messageId: messageId.value,
      content: updatedContent,
    });
  } catch (error) {
    pendingStates.value = { ...pendingStates.value };
    delete pendingStates.value[item.lineIndex];
    isUpdating.value = false;
    savingLineIndex.value = null;
    useAlert(t('CONVERSATION.PRIVATE_NOTES.TODO.UPDATE_ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <template
      v-for="(section, index) in sections"
      :key="`${section.type}-${index}`"
    >
      <FormattedContent
        v-if="section.type === 'text'"
        :content="section.content"
      />

      <div
        v-else
        class="rounded-xl border border-n-amber-12/10 bg-n-alpha-2 px-3 py-3"
      >
        <div class="mb-3 flex items-center justify-between gap-3">
          <p
            class="text-xs font-medium uppercase tracking-[0.08em] text-n-amber-12/70"
          >
            {{ $t('CONVERSATION.PRIVATE_NOTES.TODO.TITLE') }}
          </p>
          <p class="text-xs text-n-amber-12/60">
            {{ progressLabel(section.items) }}
          </p>
        </div>

        <div class="flex flex-col gap-2">
          <div
            v-for="item in section.items"
            :key="item.lineIndex"
            class="flex items-start gap-3 rounded-lg px-2 py-2 transition-colors duration-200"
            :class="{
              'bg-n-alpha-2/80': savingLineIndex === item.lineIndex,
              'hover:bg-n-alpha-2/60': savingLineIndex !== item.lineIndex,
            }"
          >
            <Checkbox
              :model-value="checkboxValue(item)"
              :disabled="isUpdating"
              class="mt-0.5 flex-shrink-0"
              @update:model-value="checked => toggleTodo(item, checked)"
            />

            <div class="min-w-0 flex-1">
              <div
                v-dompurify-html="formatTodoLabel(item.label)"
                class="prose prose-bubble max-w-none break-words [&_p]:!my-0"
                :class="{
                  'line-through text-n-amber-12/60 [&_a]:text-n-amber-12/70':
                    checkboxValue(item),
                }"
              />
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>

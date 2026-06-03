import { useState, useRef, useCallback, type KeyboardEvent, type ChangeEvent } from "react";
import type { FileAttachment } from "../api/client";

interface ChatInputProps {
  onSend: (text: string, attachments?: FileAttachment[]) => void;
  disabled: boolean;
  enableAttachments?: boolean;
}

export default function ChatInput({ onSend, disabled, enableAttachments }: ChatInputProps) {
  const [text, setText] = useState("");
  const [files, setFiles] = useState<FileAttachment[]>([]);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleSend = () => {
    if ((!text.trim() && files.length === 0) || disabled) return;
    onSend(text.trim(), files.length > 0 ? files : undefined);
    setText("");
    setFiles([]);
  };

  const handleKeyDown = (e: KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const handleFileSelect = useCallback((e: ChangeEvent<HTMLInputElement>) => {
    const selected = e.target.files;
    if (!selected) return;

    Array.from(selected).forEach((file) => {
      const reader = new FileReader();
      reader.onload = () => {
        setFiles((prev) => [
          ...prev,
          { name: file.name, type: file.type, dataUrl: reader.result as string },
        ]);
      };
      reader.readAsDataURL(file);
    });

    // Reset so the same file can be re-selected
    e.target.value = "";
  }, []);

  const removeFile = (index: number) => {
    setFiles((prev) => prev.filter((_, i) => i !== index));
  };

  const canSend = text.trim() || files.length > 0;

  return (
    <div className="border-t border-gray-200 bg-white px-4 py-3 dark:border-gray-800 dark:bg-gray-950">
      <div className="mx-auto max-w-3xl">
        {/* File preview chips */}
        {files.length > 0 && (
          <div className="mb-2 flex flex-wrap gap-2">
            {files.map((file, i) => (
              <div
                key={`${file.name}-${i}`}
                className="flex items-center gap-1.5 rounded-lg border border-gray-200 bg-gray-50 px-2.5 py-1.5 text-xs dark:border-gray-700 dark:bg-gray-800"
              >
                <span className="material-icons-outlined text-[14px] text-gray-500">
                  {file.type.startsWith("image/") ? "image" : file.type.startsWith("video/") ? "videocam" : file.type.startsWith("audio/") ? "audiotrack" : "picture_as_pdf"}
                </span>
                <span className="max-w-[150px] truncate text-gray-700 dark:text-gray-300">
                  {file.name}
                </span>
                <button
                  onClick={() => removeFile(i)}
                  className="ml-0.5 text-gray-400 hover:text-red-500"
                >
                  <span className="material-icons-outlined text-[14px]">close</span>
                </button>
              </div>
            ))}
          </div>
        )}

        <div className="flex items-end gap-2">
          {/* Attach button — only shown when CU is enabled */}
          {enableAttachments && (
            <>
              <input
                ref={fileInputRef}
                type="file"
                accept=".pdf,.docx,.xlsx,.pptx,.txt,.html,.md,.rtf,.xml,.eml,.msg,image/jpeg,image/png,image/tiff,image/bmp,image/heif,image/heic,.wav,.mp3,.m4a,.flac,.ogg,.opus,.wma,.aac,.amr,.3gpp,.mp4,.mov,.avi,.webm,.flv"
                multiple
                onChange={handleFileSelect}
                className="hidden"
              />
              <button
                onClick={() => fileInputRef.current?.click()}
                disabled={disabled}
                className="flex h-[42px] w-[42px] items-center justify-center rounded-xl border border-gray-300 bg-white text-gray-500 hover:bg-gray-50 hover:text-gray-700 disabled:opacity-50 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-400 dark:hover:bg-gray-800"
                title="Attach files"
              >
                <span className="material-icons-outlined text-[20px]">add</span>
              </button>
            </>
          )}

          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Ask Fibey something..."
            disabled={disabled}
            rows={1}
            className="flex-1 resize-none rounded-xl border border-gray-300 bg-white px-4 py-2.5 text-sm outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500 disabled:opacity-50 dark:border-gray-700 dark:bg-gray-900"
          />
          <button
            onClick={handleSend}
            disabled={disabled || !canSend}
            className="flex items-center gap-1.5 rounded-xl bg-blue-600 px-4 py-2.5 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-50"
          >
            <span className="material-icons-outlined text-[18px]">send</span>
            Send
          </button>
        </div>
      </div>
    </div>
  );
}

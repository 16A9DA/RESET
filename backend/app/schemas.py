"""Wire format shared with the iOS app (ResetCore AIRequest / AIResponse). Field names are camelCase on purpose."""
from typing import Annotated, Any, Literal, Union

from pydantic import BaseModel, ConfigDict, Field

MAX_IMAGE_B64 = 6_000_000
ALLOWED_MIME = {"image/jpeg", "image/png", "image/webp", "image/gif"}


class TextPart(BaseModel):
    model_config = ConfigDict(extra="forbid")
    type: Literal["text"]
    text: Annotated[str, Field(max_length=20_000)]


class ImagePart(BaseModel):
    model_config = ConfigDict(extra="forbid")
    type: Literal["image"]
    mime: Literal["image/jpeg", "image/png", "image/webp", "image/gif"]
    base64: Annotated[str, Field(max_length=MAX_IMAGE_B64)]


class ToolUsePart(BaseModel):
    model_config = ConfigDict(extra="forbid")
    type: Literal["tool_use"]
    id: Annotated[str, Field(max_length=200)]
    name: Annotated[str, Field(pattern=r"^[a-zA-Z0-9_-]{1,128}$")]
    input: dict[str, Any]


class ToolResultPart(BaseModel):
    model_config = ConfigDict(extra="forbid")
    type: Literal["tool_result"]
    id: Annotated[str, Field(max_length=200)]
    text: Annotated[str, Field(max_length=50_000)]
    is_error: bool = False


Part = Annotated[Union[TextPart, ImagePart, ToolUsePart, ToolResultPart], Field(discriminator="type")]


class Message(BaseModel):
    model_config = ConfigDict(extra="forbid")
    role: Literal["user", "assistant"]
    parts: Annotated[list[Part], Field(min_length=1, max_length=20)]


class Tool(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: Annotated[str, Field(pattern=r"^[a-zA-Z0-9_-]{1,128}$")]
    description: Annotated[str, Field(max_length=2_000)]
    schema_: dict[str, Any] = Field(alias="schema")


class AIRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    system: Annotated[str, Field(max_length=20_000)]
    messages: Annotated[list[Message], Field(max_length=40)]
    tools: Annotated[list[Tool], Field(max_length=20)] = []
    maxTokens: Annotated[int, Field(ge=1, le=2_000)] = 1_500


class ToolCall(BaseModel):
    id: str
    name: str
    input: dict[str, Any]


class AIResponse(BaseModel):
    text: str
    toolCalls: list[ToolCall] = []

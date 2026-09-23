defmodule TcmEdu.Storage do
  @moduledoc """
  Ash domain hosting storage resources (Blob, CourseAttachment).
  """

  use Ash.Domain,
    otp_app: :tcm_edu

  resources do
    resource TcmEdu.Storage.Blob
    resource TcmEdu.Storage.CourseAttachment
  end
end
